import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createTestApp } from "./support/app.ts";
import { closeOwnerPool, ownerQuery, seedUniversity, type University } from "./support/db.ts";

let t: Awaited<ReturnType<typeof createTestApp>>;

beforeAll(async () => {
  t = await createTestApp();
});

afterAll(async () => {
  await t.close();
  await closeOwnerPool();
});

const call = async (method: "GET" | "POST" | "DELETE", url: string, sub: string, payload?: object) =>
  t.app.inject({ method, url, headers: { authorization: `Bearer ${await t.tokenFor(sub)}` }, ...(payload && { payload }) });
const post = (sectionId: string, sub: string) => call("POST", "/enrollments", sub, { sectionId });
const del = (sectionId: string, sub: string) => call("DELETE", `/enrollments/${sectionId}`, sub);
const mine = (sub: string) => call("GET", "/me/enrollments", sub);

it("asks for a token", async () => {
  const u = await seedUniversity();
  for (const [method, url] of [
    ["GET", "/me/enrollments"],
    ["POST", "/enrollments"],
    ["DELETE", `/enrollments/${u.sections.cs101}`],
  ] as const) {
    expect((await t.app.inject({ method, url })).statusCode).toBe(401);
  }
});

it("registers a student and lists the enrolment", async () => {
  const u = await seedUniversity();
  const r = await post(u.sections.cs101, u.users.student);
  expect(r.statusCode).toBe(201);
  expect(r.json()).toMatchObject({ enrollment: { sectionId: u.sections.cs101, status: "enrolled", waitlistPosition: null } });
  expect((await mine(u.users.student)).json().enrollments).toEqual([expect.objectContaining({
    sectionId: u.sections.cs101, sectionCode: "L1", termId: u.termId, status: "enrolled",
    course: { code: "CS101", title: "Programming I", creditHours: 3.5 } })]);
});

it("lists every status by course code, and only the caller's own rows", async () => {
  const u = await seedUniversity();
  // MA101 is inserted first, as a dropped row, so the order cannot be the order of insertion.
  await ownerQuery(
    `insert into public.enrollments (tenant_id, student_id, section_id, offering_id, status)
     values ($1, $2, $3, $4, 'dropped')`,
    [u.tenantId, u.users.student, u.sections.ma101, u.offerings.ma101],
  );
  await post(u.sections.cs101, u.users.student);
  await post(u.sections.cs101, u.users.classmate);

  const r = await mine(u.users.student);
  expect(r.statusCode).toBe(200);
  expect(r.json().enrollments.map((e: { course: { code: string }; status: string }) => [e.course.code, e.status])).toEqual([
    ["CS101", "enrolled"],
    ["MA101", "dropped"],
  ]);
  // The teacher of CS101 may read its students' enrolments, but this list is the caller's own.
  expect((await mine(u.users.teacher)).json()).toEqual({ enrollments: [] });
});

it("waitlists, then refuses, when the section fills", async () => {
  const u = await seedUniversity({ cs101Capacity: 1, cs101Waitlist: 1 });
  await post(u.sections.cs101, u.users.student);
  expect((await post(u.sections.cs101, u.users.classmate)).json().enrollment).toMatchObject({ status: "waitlisted", waitlistPosition: 1 });
  const full = await post(u.sections.cs101, u.users.latecomer);
  expect([full.statusCode, full.json()]).toEqual([422, { error: { code: "rule_violation", message: "This section is full" } }]);
});

it.each([
  ["missing prerequisite", (u: University) => post(u.sections.cs201, u.users.student), 422, "rule_violation", "Prerequisites for CS201 are not met"],
  ["teacher registering", (u: University) => post(u.sections.cs101, u.users.teacher), 403, "forbidden", "You are not allowed to do that."],
])("refuses a %s", async (_label, act, status, code, message) => {
  const r = await act(await seedUniversity());
  expect([r.statusCode, r.json()]).toEqual([status, { error: { code, message } }]);
});

it("refuses a duplicate registration", async () => {
  const u = await seedUniversity();
  await post(u.sections.cs101, u.users.student);
  const r = await post(u.sections.cs101, u.users.student);
  expect([r.statusCode, r.json().error]).toEqual([409, { code: "conflict", message: "Already registered in a lecture section of this course" }]);
});

it("refuses when registration is closed", async () => {
  const u = await seedUniversity({ registrationOpen: false });
  expect((await post(u.sections.cs101, u.users.student)).json().error).toEqual({ code: "rule_violation", message: "Registration is closed for this term" });
});

it("does not reveal another university's section", async () => {
  const [u, other] = [await seedUniversity(), await seedUniversity()];
  expect((await post(other.sections.cs101, u.users.student)).json().error).toEqual({ code: "not_found", message: "Section not found" });
});

it("answers 404 for a section that does not exist", async () => {
  const u = await seedUniversity();
  const r = await post(randomUUID(), u.users.student);
  expect([r.statusCode, r.json().error]).toEqual([404, { code: "not_found", message: "Section not found" }]);
});

it("rejects a malformed section id", async () => {
  const u = await seedUniversity();
  expect((await post("x", u.users.student)).statusCode).toBe(400);
  expect((await del("x", u.users.student)).statusCode).toBe(400);
  expect((await call("POST", "/enrollments", u.users.student, {})).statusCode).toBe(400);
});

it("drops, and promotes the head of the waiting list", async () => {
  const u = await seedUniversity({ cs101Capacity: 1, cs101Waitlist: 1 });
  await post(u.sections.cs101, u.users.student);
  await post(u.sections.cs101, u.users.classmate);
  const r = await del(u.sections.cs101, u.users.student);
  expect([r.statusCode, r.json().enrollment.status]).toEqual([200, "dropped"]);
  expect((await mine(u.users.classmate)).json().enrollments[0]).toMatchObject({ status: "enrolled", waitlistPosition: null });
});

it("refuses to drop a section the student is not in", async () => {
  const u = await seedUniversity();
  expect((await del(u.sections.cs101, u.users.student)).json().error).toEqual({ code: "not_found", message: "You are not registered in this section" });
});

it("does not let a student drop a section of another university", async () => {
  const [u, other] = [await seedUniversity(), await seedUniversity()];
  await post(other.sections.cs101, other.users.student);
  const r = await del(other.sections.cs101, u.users.student);
  expect([r.statusCode, r.json().error]).toEqual([404, { code: "not_found", message: "You are not registered in this section" }]);
  expect((await mine(other.users.student)).json().enrollments[0].status).toBe("enrolled");
});
