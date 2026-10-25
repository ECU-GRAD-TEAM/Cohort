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

// How Postgres words its own constraint violations, for example `duplicate key value violates
// unique constraint "name"` or `new row for relation "t" violates check constraint "name"`. The
// registration functions never name a constraint.
const NAMES_A_CONSTRAINT = /constraint "|violates .*constraint/;

/**
 * Maps a failed query to the API error the client should see, by SQLSTATE (see the error table in
 * the design spec). Returns null for anything that is not a PostgreSQL error from Prisma.
 *
 * The database's own message is passed on only where the spec says so: the registration
 * functions write those messages for users. Postgres's own messages name tables and constraints,
 * and error responses must not. A permission failure or a foreign-key violation therefore gets a
 * fixed message, and so does a unique, exclusion or check violation whose message names a
 * constraint. Every other failure gets the fixed 500 message.
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
      return new ApiError(
        422,
        "rule_violation",
        NAMES_A_CONSTRAINT.test(originalMessage) ? "That value is not allowed." : originalMessage,
      );
    case "23503":
      return new ApiError(422, "rule_violation", "That refers to something that does not exist.");
    case "23505":
    case "23P01":
      return new ApiError(
        409,
        "conflict",
        NAMES_A_CONSTRAINT.test(originalMessage)
          ? "That conflicts with something that already exists."
          : originalMessage,
      );
    default:
      return new ApiError(500, "internal", INTERNAL_MESSAGE);
  }
}
