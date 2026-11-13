import { afterAll, beforeAll, expect, it } from "vitest";
import type { AuthClaims } from "../src/auth.ts";
import { createPrisma, withUserContext } from "../src/db.ts";
import { apiDatabaseUrl, closeOwnerPool, enrol, seedUniversity, type University } from "./support/db.ts";

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
  await enrol(a, a.users.student, "cs101");
  const enrolledAs = async (sub: string) =>
    (await withUserContext(prisma, claimsFor(sub), (tx) =>
      tx.$queryRaw<{ enrolled: boolean }[]>`select private.enrolled_in_section(${a.sections.cs101}::uuid) as enrolled`))[0]!.enrolled;
  expect(await enrolledAs(a.users.student)).toBe(true);
  expect(await enrolledAs(a.users.classmate)).toBe(false);
});

it("lets a teacher read the enrolments of the students they teach, and no one else's", async () => {
  // The student is assigned to the meetings of CS101's L1 section, which the teacher teaches.
  await enrol(a, a.users.classmate, "cs101");
  await enrol(a, a.users.latecomer, "cs201");
  const visibleTo = (sub: string) =>
    withUserContext(prisma, claimsFor(sub), (tx) =>
      tx.enrollments.findMany({ select: { student_id: true }, orderBy: { student_id: "asc" } }));
  expect((await visibleTo(a.users.teacher)).map((e) => e.student_id)).toContain(a.users.classmate);
  expect((await visibleTo(a.users.teacher)).map((e) => e.student_id)).not.toContain(a.users.latecomer);
  expect((await visibleTo(a.users.latecomer)).map((e) => e.student_id)).toEqual([a.users.latecomer]);
});
