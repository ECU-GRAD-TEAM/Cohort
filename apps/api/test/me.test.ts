import { afterAll, beforeAll, expect, it } from "vitest";
import { createTestApp } from "./support/app.ts";
import { closeOwnerPool, createAuthOnlyUser, seedUniversity, type University } from "./support/db.ts";

let t: Awaited<ReturnType<typeof createTestApp>>;
let u: University;

beforeAll(async () => {
  [t, u] = await Promise.all([createTestApp(), seedUniversity()]);
});

afterAll(async () => {
  await t.close();
  await closeOwnerPool();
});

const get = (url: string, token?: string) =>
  t.app.inject({ method: "GET", url, headers: token ? { authorization: `Bearer ${token}` } : {} });

it("is healthy without a token", async () => {
  expect((await get("/health")).json()).toEqual({ status: "ok" });
});

it("asks for a token", async () => {
  const r = await get("/me");
  expect(r.statusCode).toBe(401);
  expect(r.json()).toEqual({ error: { code: "unauthorized", message: "Sign in to continue." } });
});

it("rejects credentials that are not a bearer token", async () => {
  const token = await t.tokenFor(u.users.student);
  for (const authorization of [`Basic ${token}`, "Bearer", token]) {
    const r = await t.app.inject({ method: "GET", url: "/me", headers: { authorization } });
    expect(r.statusCode).toBe(401);
    expect(r.json().error.code).toBe("unauthorized");
  }
});

it("rejects a token signed by another key", async () => {
  expect((await get("/me", await t.foreignTokenFor(u.users.student))).statusCode).toBe(401);
});

it("describes the signed-in student", async () => {
  const r = await get("/me", await t.tokenFor(u.users.student));
  expect(r.statusCode).toBe(200);
  expect(r.json()).toMatchObject({
    id: u.users.student,
    userType: "student",
    displayName: "Sara Student",
    tenant: { id: u.tenantId, name: u.tenantName },
    roles: ["student"],
  });
});

it("explains an account that is not linked to a university", async () => {
  const r = await get("/me", await t.tokenFor(await createAuthOnlyUser()));
  expect(r.statusCode).toBe(403);
  expect(r.json()).toEqual({
    error: { code: "forbidden", message: "Your account is not linked to a university yet." },
  });
});

it("allows the web origin", async () => {
  const r = await t.app.inject({
    method: "OPTIONS",
    url: "/me",
    headers: { origin: "http://localhost:5173", "access-control-request-method": "GET" },
  });
  expect(r.headers["access-control-allow-origin"]).toBe("http://localhost:5173");
});
