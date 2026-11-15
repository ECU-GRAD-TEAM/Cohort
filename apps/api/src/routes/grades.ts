import { GradesResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";
import type { Prisma } from "../generated/prisma/client.ts";

type StudentAssessmentRow = {
  result_id: string;
  offering_id: string | null;
  course_code: string;
  course_title: string;
  term_name: string | null;
  component_id: string | null;
  component_name: string | null;
  component_type: string;
  score: Prisma.Decimal | null;
  max_score: Prisma.Decimal | null;
  recorded_at: Date | null;
  attempt_number: number | null;
  component_weight: Prisma.Decimal | null;
  score_percentage: Prisma.Decimal | null;
};

type StudentCourseRow = {
  enrollment_id: string;
  course_code: string;
  course_title: string;
  term_name: string | null;
  enrollment_status: string;
  credit_hours: Prisma.Decimal | null;
  final_percentage: Prisma.Decimal | null;
  final_grade_letter: string | null;
  final_grade_points: Prisma.Decimal | null;
  attempt_number: number | null;
};

/** Student grades are read from the dedicated course and assessment views. */
export const gradeRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  api.get("/me/grades", { schema: { response: { 200: GradesResponse } } }, async (request) => {
    const [assessmentRows, courseRows] = await request.withDb(async (tx) => Promise.all([
      tx.$queryRaw<StudentAssessmentRow[]>`
        select result_id, offering_id, course_code, course_title, term_name,
               component_id, component_name, component_type, score, max_score,
               recorded_at, attempt_number, component_weight, score_percentage
        from public.student_assessments
        where student_id = ${request.user.sub}::uuid
        order by recorded_at desc nulls last, course_code, result_id
      `,
      tx.$queryRaw<StudentCourseRow[]>`
        select enrollment_id, course_code, course_title, term_name, enrollment_status,
               credit_hours, final_percentage, final_grade_letter, final_grade_points,
               attempt_number
        from public.student_courses
        where student_id = ${request.user.sub}::uuid
        order by recorded_at desc nulls last, course_code, enrollment_id
      `,
    ]));

    return {
      grades: assessmentRows
        .filter((row) => row.score !== null && row.max_score !== null && row.recorded_at !== null)
        .map((row) => ({
          id: row.result_id,
          offeringId: row.offering_id,
          course: { code: row.course_code, title: row.course_title },
          componentId: row.component_id,
          item: row.component_name,
          score: toNumber(row.score!),
          maxScore: toNumber(row.max_score!),
          publishedAt: row.recorded_at!.toISOString(),
          attemptNumber: row.attempt_number,
          componentType: row.component_type,
          weight: row.component_weight === null ? null : toNumber(row.component_weight),
          percentage: row.score_percentage === null ? null : toNumber(row.score_percentage),
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
        attemptNumber: row.attempt_number,
      })),
    };
  });
};
