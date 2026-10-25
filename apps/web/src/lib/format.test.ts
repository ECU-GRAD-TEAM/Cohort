import type { EnrollmentStatus } from "@cohort/contracts";
import { describe, expect, it } from "vitest";
import { formatEnrollmentStatus, formatScore } from "./format.ts";

describe("formatEnrollmentStatus", () => {
  it("shows the waiting-list position for a waitlisted enrolment", () => {
    expect(formatEnrollmentStatus("waitlisted", 2)).toBe("Waitlisted (position 2)");
  });

  it("omits the position when a waitlisted enrolment has none", () => {
    expect(formatEnrollmentStatus("waitlisted", null)).toBe("Waitlisted");
  });

  it("labels every other status", () => {
    const labels: Array<[EnrollmentStatus, string]> = [
      ["enrolled", "Enrolled"],
      ["dropped", "Dropped"],
      ["withdrawn", "Withdrawn"],
      ["completed", "Completed"],
      ["failed", "Failed"],
      ["incomplete", "Incomplete"],
    ];
    for (const [status, label] of labels) {
      expect(formatEnrollmentStatus(status, null)).toBe(label);
    }
  });
});

describe("formatScore", () => {
  it("writes the score over the maximum", () => {
    expect(formatScore(75, 100)).toBe("75 / 100");
    expect(formatScore(17.5, 20)).toBe("17.5 / 20");
  });
});
