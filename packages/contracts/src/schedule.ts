import { z } from "zod";
import { Meeting } from "./catalogue.ts";

/**
 * One weekly class meeting on the caller's timetable: one a registrar assigned them to as a
 * student, or one of a section they teach. `instructors` are the section's teachers by display
 * name, which everyone at the university can see.
 */
export const ScheduleMeeting = Meeting.extend({
  id: z.uuid(),
  type: z.string(),
  building: z.string().nullable(),
  course: z.object({ code: z.string(), title: z.string() }),
  section: z.object({ id: z.uuid(), code: z.string() }),
  instructors: z.array(z.string()),
  role: z.enum(["student", "teacher"]),
});
export type ScheduleMeeting = z.infer<typeof ScheduleMeeting>;

export const ScheduleResponse = z.object({ meetings: z.array(ScheduleMeeting) });
export type ScheduleResponse = z.infer<typeof ScheduleResponse>;

/** A section the caller teaches, with how many enrolled students are assigned to its meetings. */
export const TeachingSection = z.object({
  id: z.uuid(),
  code: z.string(),
  kind: z.enum(["lecture", "lab", "tutorial"]),
  capacity: z.int().nullable(),
  termId: z.uuid(),
  course: z.object({ code: z.string(), title: z.string(), creditHours: z.number() }),
  students: z.int().min(0),
});
export type TeachingSection = z.infer<typeof TeachingSection>;

export const TeachingResponse = z.object({ sections: z.array(TeachingSection) });
export type TeachingResponse = z.infer<typeof TeachingResponse>;
