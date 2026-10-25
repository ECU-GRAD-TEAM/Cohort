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

/**
 * The caller's own current grades. `published_grades` is a view Prisma does not model, so this is
 * raw SQL; the caller's id is a bound parameter. The view and row-level security decide which
 * entries are visible, so the only filter here is whose grades the list is for.
 *
 * `item` is the component's name, found by a left join, so it is null both for a whole-course
 * grade (`componentId` is null) and for a component that row-level security hides from the
 * caller, which students see only once it is published (`componentId` is set).
 */
export const gradeRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  api.get("/me/grades", { schema: { response: { 200: GradesResponse } } }, async (request) => {
    const rows = await request.withDb((tx) =>
      tx.$queryRaw<GradeRow[]>`
        select g.id, g.offering_id, c.code as course_code, c.title as course_title,
               g.component_id, gc.name as item, g.score, g.max_score, g.published_at
        from public.published_grades g
        join public.course_offerings o on o.id = g.offering_id
        join public.courses c on c.id = o.course_id
        left join public.grade_components gc on gc.id = g.component_id
        where g.student_id = ${request.user.sub}::uuid
        order by c.code, g.published_at, g.id`,
    );
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
    };
  });
};
