import { randomUUID } from "node:crypto";
import { beforeAll, expect, it } from "vitest";
import { UnauthorizedError } from "../src/auth.ts";
import { createTestAuth, type TestAuth } from "./support/tokens.ts";

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
