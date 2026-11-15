import { EnrollmentsResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";

/**
 * A student's enrolments. Enrolment is per course offering, and registrars create it and assign the
 * student to class meetings, so the API only reads it. A historical transcript record has a course
 * and a term but no offering.
 */
export const enrollmentRoutes: FastifyPluginAsync = async (app) => {
  app.withTypeProvider<ZodTypeProvider>().get(
    "/me/enrollments",
    { schema: { response: { 200: EnrollmentsResponse } } },
    async (request) => {
      const course = { select: { code: true, title: true, credit_hours: true } } as const;
      // The caller's own rows. This is not an access rule: row-level security may let some callers
      // read other students' enrolments, and this list is only ever the caller's. One query at a
      // time: a transaction has a single connection (see `withDb`), so the assigned meetings are a
      // second query rather than a relation of the first.
      const { rows, meetings } = await request.withDb(async (tx) => {
        const rows = await tx.enrollments.findMany({
          where: { student_id: request.user.sub },
          select: {
            id: true,
            status: true,
            waitlist_position: true,
            term_id: true,
            courses: course,
            course_offerings: { select: { term_id: true, courses: course } },
          },
        });
        const meetings = await tx.student_meetings.findMany({
          where: { enrollment_id: { in: rows.map((row) => row.id) } },
          select: { enrollment_id: true, section_meetings: { select: { sections: { select: { id: true, code: true } } } } },
        });
        return { rows, meetings };
      });

      const sectionsByEnrollment = new Map<string, Map<string, string>>();
      for (const meeting of meetings) {
        const sections = sectionsByEnrollment.get(meeting.enrollment_id) ?? new Map<string, string>();
        sections.set(meeting.section_meetings.sections.id, meeting.section_meetings.sections.code);
        sectionsByEnrollment.set(meeting.enrollment_id, sections);
      }

      const enrollments = rows.flatMap((row) => {
        const found = row.course_offerings?.courses ?? row.courses;
        const termId = row.course_offerings?.term_id ?? row.term_id;
        // The database requires one of the two shapes, so neither is missing in practice.
        if (!found || !termId) return [];
        const sections = sectionsByEnrollment.get(row.id) ?? new Map<string, string>();
        return [
          {
            id: row.id,
            termId,
            status: row.status,
            waitlistPosition: row.waitlist_position,
            course: { code: found.code, title: found.title, creditHours: toNumber(found.credit_hours) },
            sections: [...sections]
              .map(([id, code]) => ({ id, code }))
              .sort((a, b) => a.code.localeCompare(b.code)),
          },
        ];
      });
      enrollments.sort((a, b) => a.course.code.localeCompare(b.course.code) || a.id.localeCompare(b.id));
      return { enrollments };
    },
  );
};
