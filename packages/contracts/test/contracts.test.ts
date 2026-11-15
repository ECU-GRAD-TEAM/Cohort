import { describe, expect, it } from "vitest";
import { ApiErrorBody, CatalogueSection, Meeting, MeResponse, Term } from "../src/index.ts";

const uuid = "0a000000-0000-4000-8000-00000000000a";

describe("contracts", () => {
  it("accepts clock times with minutes and rejects unpadded ones", () => {
    expect(Meeting.parse({ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: "101" }).startsAt).toBe("09:05");
    expect(Meeting.safeParse({ weekday: 1, startsAt: "9:5", endsAt: "10:30", room: null }).success).toBe(false);
    expect(Meeting.safeParse({ weekday: 8, startsAt: "09:00", endsAt: "10:30", room: null }).success).toBe(false);
  });
  it("keeps fractional credit hours", () => {
    const s = CatalogueSection.parse({ id: uuid, code: "L1", kind: "lecture", capacity: null,
      course: { id: uuid, code: "CS101", title: "Programming I", creditHours: 3.5 }, meetings: [] });
    expect(s.course.creditHours).toBe(3.5);
  });
  it("allows terms without a registration window", () => {
    expect(Term.safeParse({ id: uuid, code: "F26", name: "Fall 2026", startsOn: "2026-09-01", endsOn: "2026-12-20",
      registrationOpensAt: null, registrationClosesAt: null, addDropEndsAt: null }).success).toBe(true);
  });
  it("takes the staff and non_staff user types, and no others", () => {
    const me = { id: uuid, email: "a@b.c", displayName: "A", tenant: { id: uuid, name: "U" }, roles: ["student"] };
    expect(MeResponse.safeParse({ ...me, userType: "non_staff" }).success).toBe(true);
    expect(MeResponse.safeParse({ ...me, userType: "staff" }).success).toBe(true);
    expect(MeResponse.safeParse({ ...me, userType: "student" }).success).toBe(false);
  });
  it("allows terms whose calendar is not set yet", () => {
    expect(Term.safeParse({ id: uuid, code: "F27", name: "Fall 2027", startsOn: null, endsOn: null,
      registrationOpensAt: null, registrationClosesAt: null, addDropEndsAt: null }).success).toBe(true);
  });
  it("rejects unknown error codes", () => {
    expect(ApiErrorBody.safeParse({ error: { code: "teapot", message: "x" } }).success).toBe(false);
  });
});
