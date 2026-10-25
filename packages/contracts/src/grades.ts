import { z } from "zod";

export const Grade = z.object({
  id: z.uuid(),
  offeringId: z.uuid(),
  course: z.object({ code: z.string(), title: z.string() }),
  item: z.string().nullable(),
  score: z.number(),
  maxScore: z.number(),
  publishedAt: z.iso.datetime(),
});
export type Grade = z.infer<typeof Grade>;

export const GradesResponse = z.object({ grades: z.array(Grade) });
export type GradesResponse = z.infer<typeof GradesResponse>;
