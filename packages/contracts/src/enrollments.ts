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

export const Enrollment = z.object({
  id: z.uuid(),
  sectionId: z.uuid(),
  sectionCode: z.string(),
  termId: z.uuid(),
  status: EnrollmentStatus,
  waitlistPosition: z.int().nullable(),
  course: z.object({
    code: z.string(),
    title: z.string(),
    creditHours: z.number(),
  }),
});
export type Enrollment = z.infer<typeof Enrollment>;

export const EnrollmentsResponse = z.object({ enrollments: z.array(Enrollment) });
export type EnrollmentsResponse = z.infer<typeof EnrollmentsResponse>;

export const EnrollRequest = z.object({ sectionId: z.uuid() });
export type EnrollRequest = z.infer<typeof EnrollRequest>;

export const SectionParams = z.object({ sectionId: z.uuid() });
export type SectionParams = z.infer<typeof SectionParams>;

export const EnrollmentChange = z.object({
  enrollment: z.object({
    id: z.uuid(),
    sectionId: z.uuid(),
    status: EnrollmentStatus,
    waitlistPosition: z.int().nullable(),
  }),
});
export type EnrollmentChange = z.infer<typeof EnrollmentChange>;
