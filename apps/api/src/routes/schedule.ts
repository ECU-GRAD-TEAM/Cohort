import { ScheduleResponse, TeachingResponse, type TeachingSection } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";
import { isoWeekday } from "./catalogue.ts";

type MeetingRow = {
  id: string;
  role: "student" | "teacher";
  type: string;
  day_of_week: number;
  starts_at: string;
  ends_at: string;
  room: string | null;
  building: string | null;
  course_code: string;
  course_title: string;
  section_id: string;
  section_code: string;
};

type InstructorRow = { section_id: string; display_name: string };

type TeachingRow = {
  id: string;
  code: string;
  kind: TeachingSection["kind"];
  capacity: number | null;
  term_id: string;
  course_code: string;
  course_title: string;
  credit_hours: Parameters<typeof toNumber>[0];
  students: number;
};

/**
 * The caller's week: the meetings a registrar assigned them to as a student, and the meetings of the
 * sections they teach. Row-level security decides what each query can see; these routes only pick
 * the caller's own rows.
 */
export const scheduleRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  api.get("/me/schedule", { schema: { response: { 200: ScheduleResponse } } }, async (request) => {
    const me = request.user.sub;
    // One query at a time: a transaction has a single connection (see `withDb`).
    const { rows, instructors } = await request.withDb(async (tx) => {
      const rows = await tx.$queryRaw<MeetingRow[]>`
        with mine as (
          select sm.meeting_id as id, 'student'::text as role
          from public.student_meetings sm
          join public.enrollments e on e.id = sm.enrollment_id and e.tenant_id = sm.tenant_id
          where e.student_id = ${me}::uuid and e.status = 'enrolled'
          union
          select m.id, 'teacher'::text
          from public.section_instructors si
          join public.section_meetings m on m.section_id = si.section_id and m.tenant_id = si.tenant_id
          where si.user_id = ${me}::uuid
        )
        select m.id, mine.role, m.meeting_type as type, m.day_of_week,
               to_char(m.starts_at, 'HH24:MI') as starts_at, to_char(m.ends_at, 'HH24:MI') as ends_at,
               r.code as room, b.name as building, c.code as course_code, c.title as course_title,
               s.id as section_id, s.code as section_code
        from mine
        join public.section_meetings m on m.id = mine.id
        join public.sections s on s.id = m.section_id and s.tenant_id = m.tenant_id
        join public.course_offerings o on o.id = m.offering_id and o.tenant_id = m.tenant_id
        join public.courses c on c.id = o.course_id and c.tenant_id = o.tenant_id
        left join public.rooms r on r.id = m.room_id and r.tenant_id = m.tenant_id
        left join public.buildings b on b.id = r.building_id and b.tenant_id = r.tenant_id`;
      const sectionIds = [...new Set(rows.map((row) => row.section_id))];
      const instructors = sectionIds.length === 0 ? [] : await tx.$queryRaw<InstructorRow[]>`
        select si.section_id, d.display_name
        from public.section_instructors si
        cross join lateral public.directory_names(array[si.user_id]) d
        where si.section_id = any(${sectionIds}::uuid[])
        order by d.display_name`;
      return { rows, instructors };
    });

    const namesBySection = new Map<string, string[]>();
    for (const { section_id, display_name } of instructors) {
      namesBySection.set(section_id, [...(namesBySection.get(section_id) ?? []), display_name]);
    }

    const meetings = rows.map((row) => ({
      id: row.id,
      type: row.type,
      weekday: isoWeekday(row.day_of_week),
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      room: row.room,
      building: row.building,
      course: { code: row.course_code, title: row.course_title },
      section: { id: row.section_id, code: row.section_code },
      instructors: namesBySection.get(row.section_id) ?? [],
      role: row.role,
    }));
    meetings.sort(
      (a, b) =>
        a.weekday - b.weekday ||
        a.startsAt.localeCompare(b.startsAt) ||
        a.endsAt.localeCompare(b.endsAt) ||
        a.course.code.localeCompare(b.course.code),
    );
    return { meetings };
  });

  api.get("/me/teaching", { schema: { response: { 200: TeachingResponse } } }, async (request) => {
    const rows = await request.withDb((tx) =>
      tx.$queryRaw<TeachingRow[]>`
        select s.id, s.code, s.kind::text as kind, s.capacity, o.term_id,
               c.code as course_code, c.title as course_title, c.credit_hours,
               (select count(distinct e.id)::int
                from public.section_meetings m
                join public.student_meetings sm on sm.meeting_id = m.id and sm.tenant_id = m.tenant_id
                join public.enrollments e on e.id = sm.enrollment_id and e.tenant_id = sm.tenant_id
                where m.section_id = s.id and e.status = 'enrolled') as students
        from public.section_instructors si
        join public.sections s on s.id = si.section_id and s.tenant_id = si.tenant_id
        join public.course_offerings o on o.id = s.offering_id and o.tenant_id = s.tenant_id
        join public.courses c on c.id = o.course_id and c.tenant_id = o.tenant_id
        where si.user_id = ${request.user.sub}::uuid
        order by c.code, s.code`,
    );
    return {
      sections: rows.map((row) => ({
        id: row.id,
        code: row.code,
        kind: row.kind,
        capacity: row.capacity,
        termId: row.term_id,
        course: { code: row.course_code, title: row.course_title, creditHours: toNumber(row.credit_hours) },
        students: row.students,
      })),
    };
  });
};
