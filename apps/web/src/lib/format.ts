import type { EnrollmentStatus } from "@cohort/contracts";

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
