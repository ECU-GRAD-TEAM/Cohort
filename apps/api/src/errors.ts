import type { ApiErrorCode } from "@cohort/contracts";
import { z } from "zod";
import { Prisma } from "./generated/prisma/client.ts";

/** The message of every 500. It never says what went wrong. */
export const INTERNAL_MESSAGE = "Something went wrong. Please try again.";

/** A failure with the status, code and message the client will receive. */
export class ApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: ApiErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

// Where Prisma's driver adapter keeps the PostgreSQL error behind a failed query.
const driverErrorMeta = z.object({
  driverAdapterError: z.object({
    cause: z.object({ originalCode: z.string(), originalMessage: z.string() }),
  }),
});

/**
 * Maps a failed query to the API error the client should see, by SQLSTATE (see the error table in
 * the design spec). Returns null for anything that is not a PostgreSQL error from Prisma.
 *
 * The database's own message is passed on only where the spec says so: the registration
 * functions write those messages for users. A permission failure or a foreign-key violation
 * names tables and constraints, so each gets a fixed message; so does every other failure.
 */
export function databaseErrorToApiError(error: unknown): ApiError | null {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError)) return null;
  const meta = driverErrorMeta.safeParse(error.meta);
  if (!meta.success) return null;
  const { originalCode, originalMessage } = meta.data.driverAdapterError.cause;

  switch (originalCode) {
    case "42501":
      return new ApiError(403, "forbidden", "You are not allowed to do that.");
    case "P0002":
      return new ApiError(404, "not_found", originalMessage);
    case "23514":
      return new ApiError(422, "rule_violation", originalMessage);
    case "23503":
      return new ApiError(422, "rule_violation", "That refers to something that does not exist.");
    case "23505":
    case "23P01":
      return new ApiError(409, "conflict", originalMessage);
    default:
      return new ApiError(500, "internal", INTERNAL_MESSAGE);
  }
}
