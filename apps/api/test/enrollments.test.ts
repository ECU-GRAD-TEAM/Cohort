import { afterAll, beforeAll, expect, it } from "vitest";
import { createTestApp } from "./support/app.ts";
import { closeOwnerPool, enrol, ownerQuery, seedUniversity } from "./support/db.ts";

let t: Awaited<ReturnType<typeof createTestApp>>;

beforeAll(async () => {
  t = await createTestApp();
});

afterAll(async () => {
  await t.close();
  await closeOwnerPool();
});

const call = async (method: "GET" | "POST" | "DELETE", url: string, sub: string) =>
  t.app.inject({ method, url, headers: { authorization: `Bearer ${await t.tokenFor(sub)}` } });
const mine = (sub: string) => call("GET", "/me/enrollments", sub);

it("asks for a token", async () => {
  expect((await t.app.inject({ method: "GET", url: "/me/enrollments" })).statusCode).toBe(401);
});

it("does not offer self-registration: registrars enrol students", async () => {
  const u = await seedUniversity();
  expect((await call("POST", "/enrollments", u.users.student)).statusCode).toBe(404);
  expect((await call("DELETE", `/enrollments/${u.sections.cs101}`, u.users.student)).statusCode).toBe(404);
});

it("lists the student's courses with the sections of their assigned meetings", async () => {
  const u = await seedUniversity();
  await enrol(u, u.users.student, "cs101");
  await enrol(u, u.users.student, "cs201", { meetings: false });

  const r = await mine(u.users.student);
  expect(r.statusCode).toBe(200);
  expect(r.json().enrollments).toEqual([
    {
      id: expect.any(String),
      termId: u.termId,
      status: "enrolled",
      waitlistPosition: null,
      course: { code: "CS101", title: "Programming I", creditHours: 3.5 },
      sections: [{ id: u.sections.cs101, code: "L1" }],
    },
    // Enrolled, but no meetings assigned yet.
    expect.objectContaining({ course: expect.objectContaining({ code: "CS201" }), sections: [] }),
  ]);
});

it("lists every status by course code, and only the caller's own rows", async () => {
  const u = await seedUniversity();
  // MA101 is enrolled first, as a dropped row, so the order cannot be the order of insertion.
  await enrol(u, u.users.student, "ma101", { status: "dropped" });
  await enrol(u, u.users.student, "cs201", { status: "waitlisted" });
  await enrol(u, u.users.student, "cs101");
  await enrol(u, u.users.classmate, "cs101");

  const r = await mine(u.users.student);
  expect(r.statusCode).toBe(200);
  expect(r.json().enrollments.map((e: { course: { code: string }; status: string }) => [e.course.code, e.status])).toEqual([
    ["CS101", "enrolled"],
    ["CS201", "waitlisted"],
    ["MA101", "dropped"],
  ]);
  // The teacher of CS101 may read its students' enrolments, but this list is only ever the caller's.
  expect((await mine(u.users.teacher)).json()).toEqual({ enrollments: [] });
});

it("includes a historical transcript record, which has a course and a term but no offering", async () => {
  const u = await seedUniversity();
  await ownerQuery(
    `insert into public.enrollments
       (tenant_id, student_id, course_id, term_id, status, credit_hours_attempted,
        final_grade_letter, final_grade_points, quality_points)
     values ($1, $2, $3, $4, 'completed', 3, 'A', 4, 12)`,
    [u.tenantId, u.users.student, u.courses.ma101, u.termId],
  );

  expect((await mine(u.users.student)).json().enrollments).toEqual([
    expect.objectContaining({
      termId: u.termId,
      status: "completed",
      course: { code: "MA101", title: "Calculus I", creditHours: 3 },
      sections: [],
    }),
  ]);
});

it("shows nothing from another university", async () => {
  const [u, other] = await Promise.all([seedUniversity(), seedUniversity()]);
  await enrol(other, other.users.student, "cs101");
  expect((await mine(u.users.student)).json()).toEqual({ enrollments: [] });
});
