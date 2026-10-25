import type { Prisma } from "./generated/prisma/client.ts";

const pad = (n: number) => String(n).padStart(2, "0");

/** `YYYY-MM-DD` from the UTC date of a `date` column. */
export function toIsoDate(d: Date): string {
  return `${String(d.getUTCFullYear()).padStart(4, "0")}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/** `HH:MM` from the UTC time of a `time` column, which Prisma returns as 1970-01-01 UTC. */
export function toClockTime(d: Date): string {
  return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

/** A `numeric` column as a number, for values such as credit hours that fit one exactly. */
export function toNumber(n: Prisma.Decimal | number): number {
  return typeof n === "number" ? n : n.toNumber();
}
