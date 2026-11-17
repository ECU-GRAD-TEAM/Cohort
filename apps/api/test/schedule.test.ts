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

const get = async (url: string, sub: string) =>
  t.app.inject({ method: "GET", url, headers: { authorization: `Bearer ${await t.tokenFor(sub)}` } });

it("asks for a token", async () => {
  for (const url of ["/me/schedule", "/me/teaching"]) {
    expect((await t.app.inject({ method: "GET", url })).statusCode).toBe(401);
  }
});

it("shows a student the meetings a registrar assigned them, with room, building and lecturer", async () => {
  const u = await seedUniversity();
  await enrol(u, u.users.student, "cs101");

  const r = await get("/me/schedule", u.users.student);
  expect(r.statusCode).toBe(200);
  expect(r.json()).toEqual({
    meetings: [
      {
        id: expect.any(String),
        type: "lecture",
        weekday: 7,
        startsAt: "09:05",
        endsAt: "10:30",
        room: "101",
        building: "Main Building",
        course: { code: "CS101", title: "Programming I" },
        section: { id: u.sections.cs101, code: "L1" },
        instructors: ["Tariq Teacher"],
        role: "student",
      },
    ],
  });
});

it("leaves out courses with no assigned meetings and enrolments that are not active", async () => {
  const u = await seedUniversity();
  await enrol(u, u.users.student, "cs101", { status: "dropped" });
  await enrol(u, u.users.student, "cs201", { meetings: false });
  expect((await get("/me/schedule", u.users.student)).json()).toEqual({ meetings: [] });
});

it("orders meetings by weekday, Sunday last, then start time", async () => {
  const u = await seedUniversity();
  await enrol(u, u.users.student, "cs101");
  // Two more CS101 L1 meetings: Monday afternoon and Monday morning (day_of_week 1).
  for (const [startsAt, endsAt] of [["13:00", "14:00"], ["08:00", "09:00"]]) {
    await ownerQuery(
      `with m as (
         insert into public.section_meetings (tenant_id, section_id, offering_id, day_of_week, starts_at, ends_at, meeting_type)
         values ($1, $2, $3, 1, $4, $5, 'lab') returning id, tenant_id)
       insert into public.student_meetings (tenant_id, enrollment_id, meeting_id)
       select m.tenant_id, e.id, m.id from m join public.enrollments e on e.student_id = $6 and e.offering_id = $3`,
      [u.tenantId, u.sections.cs101, u.offerings.cs101, startsAt, endsAt, u.users.student],
    );
  }
  const meetings = (await get("/me/schedule", u.users.student)).json().meetings;
  expect(meetings.map((m: { weekday: number; startsAt: string; room: string | null }) => [m.weekday, m.startsAt, m.room])).toEqual([
    [1, "08:00", null],
    [1, "13:00", null],
    [7, "09:05", "101"],
  ]);
});

it("shows a teacher the meetings of the sections they teach", async () => {
  const u = await seedUniversity();
  const meetings = (await get("/me/schedule", u.users.teacher)).json().meetings;
  expect(meetings).toEqual([
    expect.objectContaining({ course: { code: "CS101", title: "Programming I" }, role: "teacher", instructors: ["Tariq Teacher"] }),
  ]);
});

it("lists a teacher's sections with the number of enrolled students assigned to them", async () => {
  const u = await seedUniversity();
  await enrol(u, u.users.student, "cs101");
  await enrol(u, u.users.classmate, "cs101");
  await enrol(u, u.users.latecomer, "cs101", { status: "dropped" });

  const r = await get("/me/teaching", u.users.teacher);
  expect(r.statusCode).toBe(200);
  expect(r.json()).toEqual({
    sections: [
      {
        id: u.sections.cs101,
        code: "L1",
        kind: "lecture",
        capacity: 30,
        termId: u.termId,
        course: { code: "CS101", title: "Programming I", creditHours: 3.5 },
        students: 2,
      },
    ],
  });
});

it("shows a student no teaching, and no one anything from another university", async () => {
  const [u, other] = await Promise.all([seedUniversity(), seedUniversity()]);
  await enrol(other, other.users.student, "cs101");
  expect((await get("/me/teaching", u.users.student)).json()).toEqual({ sections: [] });
  expect((await get("/me/schedule", u.users.student)).json()).toEqual({ meetings: [] });
  expect((await get("/me/teaching", u.users.teacher)).json().sections.map((s: { id: string }) => s.id)).toEqual([u.sections.cs101]);
});
