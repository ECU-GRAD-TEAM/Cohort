import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, expect, it } from "vitest";
import { createTestApp } from "./support/app.ts";
import { closeOwnerPool, ownerQuery, seedUniversity, type University } from "./support/db.ts";

let t: Awaited<ReturnType<typeof createTestApp>>;
let u: University;
let other: University;
let student: string;

beforeAll(async () => {
  [t, u, other] = await Promise.all([createTestApp(), seedUniversity(), seedUniversity()]);
  student = await t.tokenFor(u.users.student);
});

afterAll(async () => {
  await t.close();
  await closeOwnerPool();
});

const get = (url: string, token?: string) =>
  t.app.inject({ method: "GET", url, headers: token ? { authorization: `Bearer ${token}` } : {} });

it("asks for a token", async () => {
  expect((await get("/terms")).statusCode).toBe(401);
  expect((await get(`/terms/${u.termId}/sections`)).statusCode).toBe(401);
});

it("lists only the caller's terms, newest first", async () => {
  await ownerQuery(`insert into public.terms (tenant_id, code, name, starts_on, ends_on) values ($1, 'OLD', 'Spring 2026', '2026-01-10', '2026-05-30')`, [u.tenantId]);
  const r = await get("/terms", student);
  expect(r.json().terms.map((t: { name: string }) => t.name)).toEqual(["Fall 2026", "Spring 2026"]);
  // Both universities have a "Fall 2026", so the names alone cannot show whose it is.
  const ids = r.json().terms.map((t: { id: string }) => t.id);
  expect(ids).toContain(u.termId);
  expect(ids).not.toContain(other.termId);
});

it("describes a term with ISO dates and timestamps", async () => {
  const v = await seedUniversity();
  await ownerQuery(
    `update public.terms set starts_on = '2026-09-05', ends_on = '2027-01-20',
       registration_opens_at = '2026-08-01T08:30:00Z', registration_closes_at = '2026-09-10T17:45:00Z',
       add_drop_ends_at = null where id = $1`,
    [v.termId],
  );
  const r = await get("/terms", await t.tokenFor(v.users.student));
  expect(r.statusCode).toBe(200);
  expect(r.json().terms).toEqual([
    {
      id: v.termId,
      code: expect.any(String),
      name: "Fall 2026",
      startsOn: "2026-09-05",
      endsOn: "2027-01-20",
      registrationOpensAt: "2026-08-01T08:30:00.000Z",
      registrationClosesAt: "2026-09-10T17:45:00.000Z",
      addDropEndsAt: null,
    },
  ]);
});

it("lists published sections with exact credits and meeting times", async () => {
  const r = await get(`/terms/${u.termId}/sections`, student);
  expect(r.statusCode).toBe(200);
  expect(r.json().sections.map((s: { course: { code: string } }) => s.course.code)).toEqual(["CS101", "CS201"]); // MA101 is a draft
  expect(r.json().sections[0]).toMatchObject({ id: u.sections.cs101, code: "L1", kind: "lecture",
    course: { code: "CS101", title: "Programming I", creditHours: 3.5 },
    meetings: [{ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: "101" }] });
});

it("orders sections by course then section code, and meetings by weekday then start", async () => {
  const v = await seedUniversity();
  // A second CS101 section, added out of order, with its meetings out of order too.
  const second = randomUUID();
  await ownerQuery(`insert into public.sections (id, tenant_id, offering_id, code, kind) values ($1, $2, $3, 'A1', 'lab')`, [second, v.tenantId, v.offerings.cs101]);
  const meet = (sectionId: string, weekday: number, startsAt: string, endsAt: string, withRoom: boolean) =>
    ownerQuery(
      `insert into public.timetable_entries (tenant_id, section_id, room_id, weekday, starts_at, ends_at, valid_from, valid_until)
       values ($1, $2, ${withRoom ? "(select id from public.rooms where tenant_id = $1)" : "null"}, $3, $4, $5, current_date, current_date + 30)`,
      [v.tenantId, sectionId, weekday, startsAt, endsAt],
    );
  await meet(second, 3, "14:00", "15:30", false);
  await meet(second, 1, "13:15", "14:00", true);
  await meet(second, 1, "08:00", "09:00", true);

  const r = await get(`/terms/${v.termId}/sections`, await t.tokenFor(v.users.student));
  expect(r.statusCode).toBe(200);
  const sections = r.json().sections;
  expect(sections.map((s: { course: { code: string }; code: string }) => `${s.course.code}/${s.code}`)).toEqual(["CS101/A1", "CS101/L1", "CS201/L1"]);
  expect(sections[0].kind).toBe("lab");
  expect(sections[0].meetings).toEqual([
    { weekday: 1, startsAt: "08:00", endsAt: "09:00", room: "101" },
    { weekday: 1, startsAt: "13:15", endsAt: "14:00", room: "101" },
    { weekday: 3, startsAt: "14:00", endsAt: "15:30", room: null },
  ]);
  expect(sections[2].meetings).toEqual([]);
});

it("does not reveal another university's term", async () => {
  const r = await get(`/terms/${other.termId}/sections`, student);
  expect(r.statusCode).toBe(404);
  expect(r.json().error.code).toBe("not_found");
});

it("answers 404 for a term that does not exist", async () => {
  const r = await get(`/terms/${randomUUID()}/sections`, student);
  expect(r.statusCode).toBe(404);
  expect(r.json()).toEqual({ error: { code: "not_found", message: "Term not found." } });
});

it("rejects a malformed term id", async () => {
  expect((await get("/terms/abc/sections", student)).json().error.code).toBe("invalid_request");
});
