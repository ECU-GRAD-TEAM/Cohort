import { GradesResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";
import type { Prisma } from "../generated/prisma/client.ts";

type StudentResultRow = {
  result_id: string;
  result_type: string;
  component_type: string;
  offering_id: string | null;
  course_code: string;
  course_title: string;
  term_name: string;
  component_id: string | null;
  component_name: string;
  score: Prisma.Decimal | null;
  max_score: Prisma.Decimal | null;
  grade_letter: string | null;
  grade_points: Prisma.Decimal | null;
  result_status: string;
  attendance_status: string | null;
  credit_hours: Prisma.Decimal | null;
  recorded_at: Date | null;
  attempt_number: number | null;
  component_weight: Prisma.Decimal | null;
  score_percentage: Prisma.Decimal | null;
};

/** Course finals and assessment/attendance records are stored in separate student-facing views. */
export const gradeRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  api.get("/me/grades", { schema: { response: { 200: GradesResponse } } }, async (request) => {
    const rows = await request.withDb((tx) => tx.$queryRaw<StudentResultRow[]>`
      select result_id, result_type, component_type, offering_id, course_code, course_title, term_name,
             component_id, component_name, score, max_score, grade_letter, grade_points,
             result_status, attendance_status, credit_hours, recorded_at, attempt_number,
             component_weight, score_percentage
      from (
        select * from public.student_courses
        union all
        select * from public.student_assessments
      ) results
      where student_id = ${request.user.sub}::uuid
      order by recorded_at desc nulls last, course_code, result_id
    `);

    return {
      grades: rows
        .filter((row) => row.result_type === "assessment" && row.score !== null && row.max_score !== null)
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
      courseResults: rows
        .filter((row) => row.result_type === "course_final")
        .map((row) => ({
          enrollmentId: row.result_id,
          course: { code: row.course_code, title: row.course_title },
          term: row.term_name,
          status: row.result_status,
          creditHours: row.credit_hours === null ? null : toNumber(row.credit_hours),
          finalPercentage: row.score === null ? null : toNumber(row.score),
          finalGradeLetter: row.grade_letter,
          finalGradePoints: row.grade_points === null ? null : toNumber(row.grade_points),
          attemptNumber: row.attempt_number,
        })),

    };
  });
};
