import type { Term } from "@cohort/contracts";
import { describe, expect, it } from "vitest";
import { pickDefaultTerm } from "./terms.ts";

const now = new Date("2026-10-25T12:00:00Z");

let nextId = 1;
function term(name: string, overrides: Partial<Term> = {}): Term {
  const id = `a0000000-0000-4000-8000-${String(nextId++).padStart(12, "0")}`;
  return {
    id,
    code: name,
    name,
    startsOn: "2026-09-01",
    endsOn: "2027-01-31",
    registrationOpensAt: null,
    registrationClosesAt: null,
    addDropEndsAt: null,
    ...overrides,
  };
}

const spring = term("Spring 2026", {
  registrationOpensAt: "2025-11-01T00:00:00Z",
  registrationClosesAt: "2026-01-31T00:00:00Z",
});
const fall = term("Fall 2026", {
  registrationOpensAt: "2026-10-01T00:00:00Z",
  registrationClosesAt: "2026-11-30T00:00:00Z",
});

describe("pickDefaultTerm", () => {
  it("picks the term whose registration window contains now", () => {
    expect(pickDefaultTerm([spring, fall], now)?.name).toBe("Fall 2026");
  });

  it("picks the first open term when several windows contain now", () => {
    const winter = term("Winter 2026", {
      registrationOpensAt: "2026-10-20T00:00:00Z",
      registrationClosesAt: "2026-12-01T00:00:00Z",
    });
    expect(pickDefaultTerm([winter, fall], now)?.name).toBe("Winter 2026");
  });

  it("falls back to the first term when no window is open", () => {
    const later = term("Later", {
      registrationOpensAt: "2027-02-01T00:00:00Z",
      registrationClosesAt: "2027-03-01T00:00:00Z",
    });
    const earlier = term("Earlier", {
      registrationOpensAt: "2025-02-01T00:00:00Z",
      registrationClosesAt: "2025-03-01T00:00:00Z",
    });
    expect(pickDefaultTerm([later, earlier], now)?.name).toBe("Later");
  });

  it("returns undefined for an empty list", () => {
    expect(pickDefaultTerm([], now)).toBeUndefined();
  });

  it("keeps a term open until add/drop ends, after registration has closed", () => {
    const addDropOnly = term("Add/drop", {
      registrationOpensAt: "2026-09-01T00:00:00Z",
      registrationClosesAt: "2026-10-24T12:00:00Z", // closed yesterday
      addDropEndsAt: "2026-10-26T12:00:00Z", // ends tomorrow
    });
    expect(pickDefaultTerm([spring, addDropOnly], now)?.name).toBe("Add/drop");
  });

  it("ends the window at add/drop when it is set, even if registration closes later", () => {
    const addDropEarly = term("Add/drop early", {
      registrationOpensAt: "2026-09-01T00:00:00Z",
      registrationClosesAt: "2026-11-30T00:00:00Z",
      addDropEndsAt: "2026-10-24T12:00:00Z",
    });
    expect(pickDefaultTerm([addDropEarly, fall], now)?.name).toBe("Fall 2026");
  });

  it("includes the instant registration opens and the instant it ends", () => {
    const opensNow = term("Opens now", {
      registrationOpensAt: "2026-10-25T12:00:00Z",
      registrationClosesAt: "2026-11-30T00:00:00Z",
    });
    const endsNow = term("Ends now", {
      registrationOpensAt: "2026-09-01T00:00:00Z",
      registrationClosesAt: "2026-10-25T12:00:00Z",
    });
    expect(pickDefaultTerm([spring, opensNow], now)?.name).toBe("Opens now");
    expect(pickDefaultTerm([spring, endsNow], now)?.name).toBe("Ends now");
  });

  it("excludes the instant before it opens and the instant after it ends", () => {
    const opensLater = term("Opens a second late", {
      registrationOpensAt: "2026-10-25T12:00:01Z",
      registrationClosesAt: "2026-11-30T00:00:00Z",
    });
    const endedBefore = term("Ended a second ago", {
      registrationOpensAt: "2026-09-01T00:00:00Z",
      registrationClosesAt: "2026-10-25T11:59:59Z",
    });
    expect(pickDefaultTerm([opensLater, fall], now)?.name).toBe("Fall 2026");
    expect(pickDefaultTerm([endedBefore, fall], now)?.name).toBe("Fall 2026");
  });

  it("never treats a term with no opening time, or no end, as open", () => {
    const noOpen = term("No open", { registrationClosesAt: "2026-11-30T00:00:00Z" });
    const noEnd = term("No end", { registrationOpensAt: "2026-09-01T00:00:00Z" });
    expect(pickDefaultTerm([noOpen, noEnd, fall], now)?.name).toBe("Fall 2026");
    expect(pickDefaultTerm([noOpen, noEnd], now)?.name).toBe("No open");
  });
});
