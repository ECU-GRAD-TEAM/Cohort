import { z } from "zod";

export const StudentGpaRecord = z.object({
  academicYear: z.string().nullable(),
  term: z.string(),
  termCode: z.string(),
  termKind: z.string(),
  termGpa: z.number().nullable(),
  cumulativeGpa: z.number().nullable(),
  termCreditsAttempted: z.number(),
  cumulativeCreditsAttempted: z.number(),
  cumulativeCreditsEarned: z.number(),
  termQualityPoints: z.number(),
  cumulativeQualityPoints: z.number(),
  computedAt: z.iso.datetime(),
});
export type StudentGpaRecord = z.infer<typeof StudentGpaRecord>;

export const StudentGpaResponse = z.object({
  records: z.array(StudentGpaRecord),
});
export type StudentGpaResponse = z.infer<typeof StudentGpaResponse>;
