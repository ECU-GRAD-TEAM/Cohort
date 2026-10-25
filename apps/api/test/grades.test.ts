import { afterAll, beforeAll, expect, it } from "vitest";
import { createTestApp } from "./support/app.ts";
import { closeOwnerPool, ownerQuery, seedUniversity, type University } from "./support/db.ts";

let t: Awaited<ReturnType<typeof createTestApp>>;
let u: University;

const enrol = async (v: University, sub: string, key: "cs101" | "ma101") =>
  (await ownerQuery<{ id: string }>(
    `insert into public.enrollments (tenant_id, student_id, section_id, offering_id, status)
     values ($1, $2, $3, $4, 'enrolled') returning id`,
    [v.tenantId, sub, v.sections[key], v.offerings[key]],
  ))[0]!.id;

const component = async (v: University, key: "cs101" | "ma101", name: string, weight: number) =>
  (await ownerQuery<{ id: string }>(
    `insert into public.grade_components (tenant_id, offering_id, name, category, weight, published_at)
     values ($1, $2, $3, 'midterm', $4, now()) returning id`,
    [v.tenantId, v.offerings[key], name, weight],
  ))[0]!.id;

/** A grade entry out of 100, as the owner. Publishing sets `published_at`, so a later insert is a later grade. */
const entry = async (
  v: University,
  e: { enrollment: string; sub: string; key: "cs101" | "ma101"; component: string | null; score: number; status: "draft" | "published"; supersedes?: string },
) =>
  (await ownerQuery<{ id: string }>(
    `insert into public.grade_entries
       (tenant_id, enrollment_id, student_id, offering_id, component_id, score, max_score, status, supersedes_id, change_reason)
     values ($1, $2, $3, $4, $5, $6, 100, $7, $8, $9) returning id`,
    [v.tenantId, e.enrollment, e.sub, v.offerings[e.key], e.component, e.score, e.status, e.supersedes ?? null,
      e.supersedes ? "Re-marked question 3" : null],
  ))[0]!.id;

beforeAll(async () => {
  [t, u] = await Promise.all([createTestApp(), seedUniversity()]);
  const enrollment = await enrol(u, u.users.student, "cs101");
  const midterm = await component(u, "cs101", "Midterm", 30);
  const grade = { enrollment, sub: u.users.student, key: "cs101", component: midterm } as const;
  await entry(u, { ...grade, score: 50, status: "draft" });
  const first = await entry(u, { ...grade, score: 70, status: "published" });
  await entry(u, { ...grade, score: 75, status: "published", supersedes: first });
});

afterAll(async () => {
  await t.close();
  await closeOwnerPool();
});

const get = (url: string, token?: string) =>
  t.app.inject({ method: "GET", url, headers: token ? { authorization: `Bearer ${token}` } : {} });

it("asks for a token", async () => {
  expect((await get("/me/grades")).statusCode).toBe(401);
});

it("shows the student their current published grades only", async () => {
  const r = await get("/me/grades", await t.tokenFor(u.users.student));
  expect(r.statusCode).toBe(200);
  expect(r.json().grades).toEqual([expect.objectContaining({ offeringId: u.offerings.cs101,
    course: { code: "CS101", title: "Programming I" }, item: "Midterm", score: 75, maxScore: 100 })]);
});

it("shows a classmate nothing", async () => {
  expect((await get("/me/grades", await t.tokenFor(u.users.classmate))).json().grades).toEqual([]);
});

it("shows the teacher none of their students' grades", async () => {
  expect((await get("/me/grades", await t.tokenFor(u.users.teacher))).json().grades).toEqual([]);
});

it("lists grades by course code then publication, with no item for an entry without a component", async () => {
  const v = await seedUniversity();
  const sub = v.users.student;
  const [cs101, ma101] = [await enrol(v, sub, "cs101"), await enrol(v, sub, "ma101")];
  const quiz = await component(v, "cs101", "Quiz", 10);
  // MA101 is published first, and "Quiz" before the whole-course grade, so neither the order of
  // insertion nor the alphabet gives the expected order.
  await entry(v, { enrollment: ma101, sub, key: "ma101", component: null, score: 88, status: "published" });
  await entry(v, { enrollment: cs101, sub, key: "cs101", component: quiz, score: 9, status: "published" });
  await entry(v, { enrollment: cs101, sub, key: "cs101", component: null, score: 90, status: "published" });

  const r = await get("/me/grades", await t.tokenFor(sub));
  expect(r.statusCode).toBe(200);
  expect(r.json().grades.map((g: { course: { code: string }; item: string | null; score: number }) => [g.course.code, g.item, g.score])).toEqual([
    ["CS101", "Quiz", 9],
    ["CS101", null, 90],
    ["MA101", null, 88],
  ]);
});
