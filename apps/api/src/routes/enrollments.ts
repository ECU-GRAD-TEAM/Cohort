import {
  EnrollmentChange,
  EnrollmentsResponse,
  EnrollRequest,
  type EnrollmentStatus,
  SectionParams,
} from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";

/** What `enroll_in_section` and `drop_section` return: the enrolment they changed. */
type ChangedRow = {
  id: string;
  section_id: string;
  status: EnrollmentStatus;
  waitlist_position: number | null;
};

/**
 * The database's registration functions decide every rule: prerequisites, credit limit, clashes,
 * capacity, waiting list and registration window. They refuse with an error the app's error
 * handler turns into a response, so these routes only call them and report the result.
 */
export const enrollmentRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  const toChange = ([row]: ChangedRow[]): EnrollmentChange => {
    // Both functions return the changed row or raise, so a missing row is a bug, not a refusal.
    if (!row) throw new Error("The registration function returned no enrolment");
    return {
      enrollment: {
        id: row.id,
        sectionId: row.section_id,
        status: row.status,
        waitlistPosition: row.waitlist_position,
      },
    };
  };

  api.get("/me/enrollments", { schema: { response: { 200: EnrollmentsResponse } } }, async (request) => {
    // The caller's own rows. This is not an access rule: row-level security may let some callers
    // read other students' enrolments, and this list is only ever the caller's.
    const enrollments = await request.withDb((tx) =>
      tx.enrollments.findMany({
        where: { student_id: request.user.sub },
        orderBy: [{ sections: { course_offerings: { courses: { code: "asc" } } } }, { sections: { code: "asc" } }, { id: "asc" }],
        select: {
          id: true,
          section_id: true,
          status: true,
          waitlist_position: true,
          sections: {
            select: {
              code: true,
              course_offerings: {
                select: { term_id: true, courses: { select: { code: true, title: true, credit_hours: true } } },
              },
            },
          },
        },
      }),
    );
    return {
      enrollments: enrollments.map((enrollment) => {
        const { code: sectionCode, course_offerings: offering } = enrollment.sections;
        return {
          id: enrollment.id,
          sectionId: enrollment.section_id,
          sectionCode,
          termId: offering.term_id,
          status: enrollment.status,
          waitlistPosition: enrollment.waitlist_position,
          course: {
            code: offering.courses.code,
            title: offering.courses.title,
            creditHours: toNumber(offering.courses.credit_hours),
          },
        };
      }),
    };
  });

  api.post(
    "/enrollments",
    { schema: { body: EnrollRequest, response: { 201: EnrollmentChange } } },
    async (request, reply) => {
      const { sectionId } = request.body;
      const rows = await request.withDb((tx) =>
        tx.$queryRaw<ChangedRow[]>`
          select id, section_id, status::text as status, waitlist_position
          from public.enroll_in_section(${sectionId}::uuid)`,
      );
      return reply.code(201).send(toChange(rows));
    },
  );

  api.delete(
    "/enrollments/:sectionId",
    { schema: { params: SectionParams, response: { 200: EnrollmentChange } } },
    async (request) => {
      const { sectionId } = request.params;
      const rows = await request.withDb((tx) =>
        tx.$queryRaw<ChangedRow[]>`
          select id, section_id, status::text as status, waitlist_position
          from public.drop_section(${sectionId}::uuid)`,
      );
      return toChange(rows);
    },
  );
};
