import type { EnrollmentStatus, Grade, Meeting, MeResponse } from "@cohort/contracts";

const STATUS_LABELS: Record<Exclude<EnrollmentStatus, "waitlisted">, string> = {
  enrolled: "Enrolled",
  dropped: "Dropped",
  withdrawn: "Withdrawn",
  completed: "Completed",
  failed: "Failed",
  incomplete: "Incomplete",
};

/** The label for an enrolment's status; a waitlisted one also says where it stands in the queue. */
export function formatEnrollmentStatus(status: EnrollmentStatus, waitlistPosition: number | null): string {
  if (status === "waitlisted") {
    return waitlistPosition === null ? "Waitlisted" : `Waitlisted (position ${waitlistPosition})`;
  }
  return STATUS_LABELS[status];
}

/** A grade as "75 / 100". */
export function formatScore(score: number, maxScore: number): string {
  return `${score} / ${maxScore}`;
}

/**
 * What a grade was for: the component's name when the student can see it, "Course grade" for a
 * grade with no component, and "Graded item" for one whose component is not published yet.
 */
export function formatGradeItem(grade: Pick<Grade, "item" | "componentId">): string {
  if (grade.item !== null) return grade.item;
  return grade.componentId === null ? "Course grade" : "Graded item";
}

// ISO weekday numbers: 1 = Monday ... 7 = Sunday.
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** A meeting as "Mon 09:00–10:30 · Room 101", without the room part when there is no room. */
export function formatMeeting(meeting: Meeting): string {
  const when = `${WEEKDAYS[meeting.weekday - 1]} ${meeting.startsAt}–${meeting.endsAt}`;
  return meeting.room === null ? when : `${when} · Room ${meeting.room}`;
}

/** An enrolment's sections as "Section L1" or "Sections L1, B2", or "No section assigned yet". */
export function formatSections(sections: { code: string }[]): string {
  if (sections.length === 0) return "No section assigned yet";
  const codes = sections.map((section) => section.code).join(", ");
  return sections.length === 1 ? `Section ${codes}` : `Sections ${codes}`;
}

/** Credit hours as "1 credit", "3 credits" or "3.5 credits": the number exactly as it is. */
export function formatCredits(creditHours: number): string {
  return creditHours === 1 ? "1 credit" : `${creditHours} credits`;
}

/** Role keys a university gives its students. */
const STUDENT_ROLES = ["undergraduate", "postgraduate"];

/** The sidebar's label for the caller: "Student" with a student role, else "Staff" or "Non-staff". */
export function formatRole(me: Pick<MeResponse, "userType" | "roles">): string {
  if (me.roles.some((role) => STUDENT_ROLES.includes(role))) return "Student";
  if (me.roles.includes("teaching_assistant")) return "Teaching Assistant";
  return me.userType === "staff" ? "Staff" : "Non-staff";
}

/** The first letters of the first and last words of a name, upper-cased; "?" for an empty name. */
export function initials(displayName: string): string {
  const words = displayName.split(/\s+/).filter((word) => word !== "");
  const first = words[0];
  const last = words[words.length - 1];
  if (first === undefined || last === undefined) return "?";
  const letters = words.length === 1 ? [first] : [first, last];
  return letters.map((word) => Array.from(word)[0] ?? "").join("").toUpperCase();
}
