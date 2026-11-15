import { z } from "zod";

/**
 * A published grade. `componentId` says which graded component it belongs to, or is null for a
 * grade of the whole course. `item` is that component's name, and is null in two cases: a
 * whole-course grade (`componentId` is null too), and a component that row-level security hides
 * from the caller because it is not published yet (`componentId` is set).
 */
export const Grade = z.object({
  id: z.uuid(),
  offeringId: z.uuid(),
  course: z.object({ code: z.string(), title: z.string() }),
  componentId: z.uuid().nullable(),
  item: z.string().nullable(),
  score: z.number(),
  maxScore: z.number(),
  publishedAt: z.iso.datetime(),
});
export type Grade = z.infer<typeof Grade>;

export const GradesResponse = z.object({ grades: z.array(Grade) });
export type GradesResponse = z.infer<typeof GradesResponse>;
