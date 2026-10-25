import { afterAll, beforeAll, expect, it } from "vitest";
import type { AuthClaims } from "../src/auth.ts";
import { createPrisma, withUserContext } from "../src/db.ts";
import { apiDatabaseUrl, closeOwnerPool, seedUniversity, type University } from "./support/db.ts";

let prisma: ReturnType<typeof createPrisma>;
let a: University;
// University b exists so that the tests below prove a's student cannot see it.
let b: University;

const claimsFor = (sub: string): AuthClaims => ({ sub, role: "authenticated" });

beforeAll(async () => {
  [a, b] = await Promise.all([seedUniversity(), seedUniversity()]);
  prisma = createPrisma(apiDatabaseUrl);
});

afterAll(async () => {
  await prisma.$disconnect();
  await closeOwnerPool();
});

it("refuses a query made outside a user context", async () => {
  await expect(prisma.courses.findMany()).rejects.toMatchObject({
    meta: { driverAdapterError: { cause: { originalCode: "42501" } } },
  });
});

it("shows a student only their own university's courses", async () => {
  const ids = await withUserContext(prisma, claimsFor(a.users.student), (tx) =>
    tx.courses.findMany({ select: { id: true } }));
  expect(ids.map((c) => c.id).sort()).toEqual([a.courses.cs101, a.courses.cs201, a.courses.ma101].sort());
});

it("runs database functions as the student", async () => {
  const rows = await withUserContext(prisma, claimsFor(a.users.student), (tx) =>
    tx.$queryRaw<{ status: string }[]>`select status::text from public.enroll_in_section(${a.sections.cs101}::uuid)`);
  expect(rows).toEqual([{ status: "enrolled" }]);
});
