import { expect, it } from "vitest";
import { Prisma } from "../src/generated/prisma/client.ts";
import { toClockTime, toIsoDate, toNumber } from "../src/format.ts";

it("formats a time column as HH:MM", () => {
  expect(toClockTime(new Date("1970-01-01T09:05:00Z"))).toBe("09:05");
  expect(toClockTime(new Date("1970-01-01T00:00:00Z"))).toBe("00:00");
  expect(toClockTime(new Date("1970-01-01T23:59:00Z"))).toBe("23:59");
});

it("formats a date column as YYYY-MM-DD", () => {
  expect(toIsoDate(new Date("2026-10-25T00:00:00Z"))).toBe("2026-10-25");
  expect(toIsoDate(new Date("2026-01-05T00:00:00Z"))).toBe("2026-01-05");
});

it("reads the UTC parts, whatever the local time zone", () => {
  // 23:30 UTC on the 25th is already the 26th, 01:30 in Cairo; the UTC parts must win.
  expect(toIsoDate(new Date("2026-10-25T23:30:00Z"))).toBe("2026-10-25");
  expect(toClockTime(new Date("1970-01-01T23:30:00Z"))).toBe("23:30");
});

it("turns a decimal into a number without losing the fraction", () => {
  expect(toNumber(new Prisma.Decimal("3.5"))).toBe(3.5);
  expect(toNumber(new Prisma.Decimal("3.0"))).toBe(3);
  expect(toNumber(2)).toBe(2);
});
