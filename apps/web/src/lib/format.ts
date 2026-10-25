import type { EnrollmentStatus, Meeting } from "@cohort/contracts";

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

// ISO weekday numbers: 1 = Monday ... 7 = Sunday.
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** A meeting as "Mon 09:00–10:30 · Room 101", without the room part when there is no room. */
export function formatMeeting(meeting: Meeting): string {
  const when = `${WEEKDAYS[meeting.weekday - 1]} ${meeting.startsAt}–${meeting.endsAt}`;
  return meeting.room === null ? when : `${when} · Room ${meeting.room}`;
}

/** Credit hours as "1 credit", "3 credits" or "3.5 credits": the number exactly as it is. */
export function formatCredits(creditHours: number): string {
  return creditHours === 1 ? "1 credit" : `${creditHours} credits`;
}
