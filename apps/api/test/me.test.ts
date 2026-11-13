import { errors } from "jose";
import { afterAll, beforeAll, expect, it } from "vitest";
import { buildApp } from "../src/app.ts";
import { createTokenVerifier } from "../src/auth.ts";
import { createPrisma } from "../src/db.ts";
import { createTestApp } from "./support/app.ts";
import {
  apiDatabaseUrl,
  closeOwnerPool,
  createAuthOnlyUser,
  ownerQuery,
  seedUniversity,
  type University,
} from "./support/db.ts";
import { TEST_ISSUER } from "./support/tokens.ts";

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

it("answers 500, not 401, when the signing keys cannot be fetched", async () => {
  // A 401 makes the web app sign the user out, so an outage on Supabase's side must not look like one.
  const prisma = createPrisma(apiDatabaseUrl);
  const app = await buildApp({
    prisma,
    verifyToken: createTokenVerifier({
      getKey: async () => {
        throw new errors.JWKSTimeout();
      },
      issuer: TEST_ISSUER,
      audience: "authenticated",
    }),
    corsOrigin: "http://localhost:5173",
  });
  try {
    const token = await t.tokenFor(u.users.student);
    const r = await app.inject({ method: "GET", url: "/me", headers: { authorization: `Bearer ${token}` } });
    expect(r.statusCode).toBe(500);
    expect(r.json()).toEqual({ error: { code: "internal", message: "Something went wrong. Please try again." } });
  } finally {
    await app.close();
    await prisma.$disconnect();
  }
});

it("describes the signed-in student", async () => {
  const r = await get("/me", await t.tokenFor(u.users.student));
  expect(r.statusCode).toBe(200);
  expect(r.json()).toMatchObject({
    id: u.users.student,
    userType: "non_staff",
    displayName: "Sara Student",
    tenant: { id: u.tenantId, name: u.tenantName },
    roles: ["undergraduate"],
  });
});

it("lists only the roles that are active now", async () => {
  // A university of its own, so the extra assignments do not change the student above.
  const v = await seedUniversity();
  const grant = (
    roleKey: string,
    { starts = "-2 days", ends = null, status = "active" }: { starts?: string; ends?: string | null; status?: string } = {},
  ) =>
    ownerQuery(
      `insert into public.user_roles (user_id, role_id, tenant_id, starts_at, ends_at, status)
       select $1, r.id, r.tenant_id, now() + $3::interval, now() + $4::interval, $5
       from public.roles r where r.tenant_id = $2 and r.key = $6`,
      [v.users.student, v.tenantId, starts, ends, status, roleKey],
    );
  // The role keys below come from the tenant's seeded roles. `status` is the assignment's lifecycle;
  // the database derives `assignment_status` and `revoked_at` from it.
  await grant("teaching_assistant", { ends: "1 day" }); // still running: listed
  await grant("academic_advisor", { starts: "-3 days", ends: "-1 day" }); // ended by its end date
  await grant("finance_officer", { status: "revoked" }); // revoked
  await grant("lecturer", { status: "ended" }); // ended early
  await grant("it_officer", { starts: "1 day" }); // not started yet

  const r = await get("/me", await t.tokenFor(v.users.student));
  expect(r.statusCode).toBe(200);
  expect(r.json().roles).toEqual(["teaching_assistant", "undergraduate"]);
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
