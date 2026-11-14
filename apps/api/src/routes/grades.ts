import { GradesResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";
import type { Prisma } from "../generated/prisma/client.ts";

type GradeRow = {
  id: string;
  offering_id: string;
  course_code: string;
  course_title: string;
  component_id: string | null;
  item: string | null;
  score: Prisma.Decimal;
  max_score: Prisma.Decimal;
  published_at: Date;
};

type CourseResultRow = {
  enrollment_id: string;
  course_code: string;
  course_title: string;
  term_name: string | null;
  enrollment_status: string;
  credit_hours: Prisma.Decimal | null;
  final_percentage: Prisma.Decimal | null;
  final_grade_letter: string | null;
  final_grade_points: Prisma.Decimal | null;
};

/** Assessment marks and final enrollment grades are returned separately to avoid mixing their meanings. */
export const gradeRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  api.get("/me/grades", { schema: { response: { 200: GradesResponse } } }, async (request) => {
    const [rows, courseRows] = await request.withDb(async (tx) => Promise.all([
      tx.$queryRaw<GradeRow[]>`
        select g.id, g.offering_id, c.code as course_code, c.title as course_title,
               g.component_id, gc.name as item, g.score, g.max_score, g.published_at
        from public.published_grades g
        join public.course_offerings o on o.id = g.offering_id
        join public.courses c on c.id = o.course_id
        left join public.grade_components gc on gc.id = g.component_id
        where g.student_id = \${request.user.sub}::uuid
        order by c.code, g.published_at, g.id`,
      tx.$queryRaw<CourseResultRow[]>`
        select enrollment_id, course_code, course_title, term_name, enrollment_status,
               credit_hours, final_percentage, final_grade_letter, final_grade_points
        from public.student_course_results
        where student_id = \${request.user.sub}::uuid
        order by term_name nulls last, course_code, enrollment_id`,
    ]));

    return {
      grades: rows.map((row) => ({
        id: row.id,
        offeringId: row.offering_id,
        course: { code: row.course_code, title: row.course_title },
        componentId: row.component_id,
        item: row.item,
        score: toNumber(row.score),
        maxScore: toNumber(row.max_score),
        publishedAt: row.published_at.toISOString(),
      })),
      courseResults: courseRows.map((row) => ({
        enrollmentId: row.enrollment_id,
        course: { code: row.course_code, title: row.course_title },
        term: row.term_name,
        status: row.enrollment_status,
        creditHours: row.credit_hours === null ? null : toNumber(row.credit_hours),
        finalPercentage: row.final_percentage === null ? null : toNumber(row.final_percentage),
        finalGradeLetter: row.final_grade_letter,
        finalGradePoints: row.final_grade_points === null ? null : toNumber(row.final_grade_points),
      })),
    };
  });
};
