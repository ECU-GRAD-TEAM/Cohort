import { z } from "zod";

export const Grade = z.object({
  id: z.uuid(),
  offeringId: z.uuid(),
  course: z.object({ code: z.string(), title: z.string() }),
  componentId: z.uuid().nullable(),
  item: z.string().nullable(),
  score: z.number(),
  maxScore: z.number(),
  publishedAt: z.iso.datetime(),
  componentType: z.string(),
  weight: z.number().nullable(),
  percentage: z.number().nullable(),
});
export type Grade = z.infer<typeof Grade>;

export const CourseResult = z.object({
  enrollmentId: z.uuid(),
  course: z.object({ code: z.string(), title: z.string() }),
  term: z.string().nullable(),
  status: z.string(),
  creditHours: z.number().nullable(),
  finalPercentage: z.number().nullable(),
  finalGradeLetter: z.string().nullable(),
  finalGradePoints: z.number().nullable(),
  attemptNumber: z.number().nullable(),
});
export type CourseResult = z.infer<typeof CourseResult>;

export const GradesResponse = z.object({
  grades: z.array(Grade),
  courseResults: z.array(CourseResult).default([]),
});
export type GradesResponse = z.infer<typeof GradesResponse>;
