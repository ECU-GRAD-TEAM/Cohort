import { randomUUID } from "node:crypto";
import { errors } from "jose";
import { beforeAll, expect, it } from "vitest";
import { createTokenVerifier, KeySetUnavailableError, UnauthorizedError } from "../src/auth.ts";
import { createTestAuth, TEST_ISSUER, type TestAuth } from "./support/tokens.ts";

let auth: TestAuth;
const sub = randomUUID();

beforeAll(async () => {
  auth = await createTestAuth();
});

it("returns the claims of a valid token", async () => {
  await expect(auth.verifyToken(await auth.tokenFor(sub))).resolves.toMatchObject({ sub, role: "authenticated" });
});

it("keeps the other claims of a valid token", async () => {
  const claims = await auth.verifyToken(await auth.tokenFor(sub, { email: "sara@cohort.test" }));
  expect(claims.email).toBe("sara@cohort.test");
});

it.each([
  ["expired", { exp: Math.floor(Date.now() / 1000) - 60 }],
  ["no expiry", { exp: undefined }],
  ["wrong audience", { aud: "anon" }],
  ["wrong issuer", { iss: "https://evil.example/auth/v1" }],
  ["anonymous role", { role: "anon" }],
  ["non-uuid subject", { sub: "not-a-uuid" }],
])("rejects a token with %s", async (_label, overrides) => {
  await expect(auth.verifyToken(await auth.tokenFor(sub, overrides))).rejects.toBeInstanceOf(UnauthorizedError);
});

it("rejects a token signed by an unknown key", async () => {
  await expect(auth.verifyToken(await auth.foreignTokenFor(sub))).rejects.toBeInstanceOf(UnauthorizedError);
});

it("rejects garbage", async () => {
  await expect(auth.verifyToken("abc")).rejects.toBeInstanceOf(UnauthorizedError);
});

it("keeps the original failure as the cause", async () => {
  const error = await auth.verifyToken("abc").catch((e: unknown) => e);
  expect(error).toBeInstanceOf(UnauthorizedError);
  expect((error as UnauthorizedError).cause).toBeInstanceOf(Error);
});

// A verifier whose key set always fails with `failure`, as the remote key set does when Supabase
// cannot be reached.
const verifierFailingWith = (failure: Error) =>
  createTokenVerifier({
    getKey: async () => {
      throw failure;
    },
    issuer: TEST_ISSUER,
    audience: "authenticated",
  });

it.each([
  ["a timeout", new errors.JWKSTimeout()],
  ["an invalid key set", new errors.JWKSInvalid("JSON Web Key Set malformed")],
  ["a network error", new TypeError("fetch failed")],
  ["an unexpected response", new errors.JOSEError("Expected 200 OK from the JSON Web Key Set HTTP response")],
])("does not blame the token when the key set fails with %s", async (_label, failure) => {
  const verify = verifierFailingWith(failure);
  const error = await verify(await auth.tokenFor(sub)).catch((e: unknown) => e);
  expect(error).not.toBeInstanceOf(UnauthorizedError);
  expect(error).toBeInstanceOf(KeySetUnavailableError);
  expect((error as KeySetUnavailableError).cause).toBe(failure);
});

it.each([
  ["no matching key", new errors.JWKSNoMatchingKey()],
  ["several matching keys", new errors.JWKSMultipleMatchingKeys()],
])("rejects the token when the key set has %s", async (_label, failure) => {
  const verify = verifierFailingWith(failure);
  await expect(verify(await auth.tokenFor(sub))).rejects.toBeInstanceOf(UnauthorizedError);
});
