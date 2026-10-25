import type { EnrollmentStatus } from "@cohort/contracts";
import { describe, expect, it } from "vitest";
import { formatCredits, formatEnrollmentStatus, formatGradeItem, formatMeeting, formatScore } from "./format.ts";

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

describe("formatGradeItem", () => {
  it("names the component", () => {
    expect(formatGradeItem({ item: "Midterm", componentId: "b1000000-0000-4000-8000-000000000001" })).toBe("Midterm");
  });

  it("calls a grade with no component the course grade", () => {
    expect(formatGradeItem({ item: null, componentId: null })).toBe("Course grade");
  });

  it("calls a grade whose component is not visible a graded item", () => {
    expect(formatGradeItem({ item: null, componentId: "b1000000-0000-4000-8000-000000000001" })).toBe("Graded item");
  });
});

describe("formatMeeting", () => {
  it("writes the weekday, an en-dashed time range and the room", () => {
    expect(formatMeeting({ weekday: 1, startsAt: "09:00", endsAt: "10:30", room: "101" })).toBe(
      "Mon 09:00–10:30 · Room 101",
    );
  });

  it("omits the room when there is none", () => {
    expect(formatMeeting({ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: null })).toBe("Sun 09:05–10:30");
  });

  it("names every weekday, 1 = Mon to 7 = Sun", () => {
    const names = [1, 2, 3, 4, 5, 6, 7].map((weekday) =>
      formatMeeting({ weekday, startsAt: "08:00", endsAt: "09:00", room: null }).slice(0, 3),
    );
    expect(names).toEqual(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]);
  });
});

describe("formatCredits", () => {
  it("uses the singular for exactly one credit", () => {
    expect(formatCredits(1)).toBe("1 credit");
  });

  it("uses the plural for every other amount, without rounding or trailing zeros", () => {
    expect([formatCredits(3), formatCredits(3.5), formatCredits(0.5), formatCredits(0)]).toEqual([
      "3 credits",
      "3.5 credits",
      "0.5 credits",
      "0 credits",
    ]);
  });
});
