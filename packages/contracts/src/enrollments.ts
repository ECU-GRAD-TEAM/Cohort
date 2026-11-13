import { z } from "zod";

export const EnrollmentStatus = z.enum([
  "enrolled",
  "waitlisted",
  "dropped",
  "withdrawn",
  "completed",
  "failed",
  "incomplete",
]);
export type EnrollmentStatus = z.infer<typeof EnrollmentStatus>;

/**
 * One course a student is enrolled in. Enrolment is per course; a registrar assigns the student to
 * class meetings, and `sections` are the sections those meetings belong to (empty until then).
 */
export const Enrollment = z.object({
  id: z.uuid(),
  termId: z.uuid(),
  status: EnrollmentStatus,
  waitlistPosition: z.int().nullable(),
  course: z.object({
    code: z.string(),
    title: z.string(),
    creditHours: z.number(),
  }),
  sections: z.array(z.object({ id: z.uuid(), code: z.string() })),
});
export type Enrollment = z.infer<typeof Enrollment>;

export const EnrollmentsResponse = z.object({ enrollments: z.array(Enrollment) });
export type EnrollmentsResponse = z.infer<typeof EnrollmentsResponse>;
