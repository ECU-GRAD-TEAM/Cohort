import { StudentGpaResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { toNumber } from "../format.ts";
import type { Prisma } from "../generated/prisma/client.ts";

type GpaRow = {
  academic_year_name: string | null;
  term_name: string;
  term_code: string;
  term_kind: string;
  term_gpa: Prisma.Decimal | null;
  cumulative_gpa: Prisma.Decimal | null;
  term_credits_attempted: Prisma.Decimal;
  cumulative_credits_attempted: Prisma.Decimal;
  cumulative_credits_earned: Prisma.Decimal;
  term_quality_points: Prisma.Decimal;
  cumulative_quality_points: Prisma.Decimal;
  gpa_computed_at: Date;
};

export const gpaRoutes: FastifyPluginAsync = async (app) => {
  app.withTypeProvider<ZodTypeProvider>().get(
    "/me/gpa",
    { schema: { response: { 200: StudentGpaResponse } } },
    async (request) => {
      const rows = await request.withDb((tx) => tx.$queryRaw<GpaRow[]>`
        select academic_year_name, term_name, term_code, term_kind,
               term_gpa, cumulative_gpa, term_credits_attempted,
               cumulative_credits_attempted, cumulative_credits_earned,
               term_quality_points, cumulative_quality_points, gpa_computed_at
        from public.student_gpa
        where student_id = ${request.user.sub}::uuid
        order by academic_year_code asc, term_sequence asc, gpa_computed_at asc
      `);
      return {
        records: rows.map((row) => ({
          academicYear: row.academic_year_name,
          term: row.term_name,
          termCode: row.term_code,
          termKind: row.term_kind,
          termGpa: row.term_gpa === null ? null : toNumber(row.term_gpa),
          cumulativeGpa: row.cumulative_gpa === null ? null : toNumber(row.cumulative_gpa),
          termCreditsAttempted: toNumber(row.term_credits_attempted),
          cumulativeCreditsAttempted: toNumber(row.cumulative_credits_attempted),
          cumulativeCreditsEarned: toNumber(row.cumulative_credits_earned),
          termQualityPoints: toNumber(row.term_quality_points),
          cumulativeQualityPoints: toNumber(row.cumulative_quality_points),
          computedAt: row.gpa_computed_at.toISOString(),
        })),
      };
    },
  );
};
