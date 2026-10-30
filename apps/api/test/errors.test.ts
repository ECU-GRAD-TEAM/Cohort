import type { FastifyInstance } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { databaseErrorToApiError } from "../src/errors.ts";
import { Prisma } from "../src/generated/prisma/client.ts";
import { createTestApp } from "./support/app.ts";

const dbError = (code: string, message: string) =>
  new Prisma.PrismaClientKnownRequestError("Raw query failed", {
    code: "P2010",
    clientVersion: "7.10.1",
    meta: { driverAdapterError: { cause: { originalCode: code, originalMessage: message } } },
  });

describe("databaseErrorToApiError", () => {
  it.each([
    ["42501", "permission denied for table x", 403, "forbidden", "You are not allowed to do that."],
    ["P0002", "Section not found", 404, "not_found", "Section not found"],
    ["23514", "Prerequisites for CS201 are not met", 422, "rule_violation", "Prerequisites for CS201 are not met"],
    ["23503", "insert violates foreign key constraint", 422, "rule_violation", "That refers to something that does not exist."],
    ["23505", "Already registered in a lecture section of this course", 409, "conflict", "Already registered in a lecture section of this course"],
    ["23505", 'duplicate key value violates unique constraint "enrollments_one_active_per_offering"', 409, "conflict", "That conflicts with something that already exists."],
    ["23P01", 'conflicting key value violates exclusion constraint "timetable_entries_no_room_clash"', 409, "conflict", "That conflicts with something that already exists."],
    ["23514", 'new row for relation "sections" violates check constraint "sections_capacity_check"', 422, "rule_violation", "That value is not allowed."],
    ["XX000", "boom", 500, "internal", "Something went wrong. Please try again."],
  ])("maps SQLSTATE %s", (code, message, status, apiCode, apiMessage) => {
    expect(databaseErrorToApiError(dbError(code, message))).toMatchObject({ statusCode: status, code: apiCode, message: apiMessage });
  });

  // The functions' own messages are written for users; Postgres's constraint messages are not.
  it.each([
    ["23505", 'duplicate key value violates unique constraint "enrollments_one_active_per_offering"', "enrollments_one_active_per_offering"],
    ["23P01", 'conflicting key value violates exclusion constraint "timetable_entries_no_room_clash"', "timetable_entries_no_room_clash"],
    ["23514", 'new row for relation "sections" violates check constraint "sections_capacity_check"', "sections_capacity_check"],
  ])("never shows the constraint named by SQLSTATE %s", (code, message, name) => {
    expect(databaseErrorToApiError(dbError(code, message))?.message).not.toContain(name);
  });

  it.each([
    "This section is full",
    "Registering would exceed the credit limit for the term",
    "The add/drop period has ended; ask the registrar to withdraw you",
  ])("passes on the check-violation message %j of a registration function", (message) => {
    expect(databaseErrorToApiError(dbError("23514", message))?.message).toBe(message);
  });

  it("ignores errors that are not database errors", () => {
    expect(databaseErrorToApiError(new Error("x"))).toBeNull();
  });
});

// The routes below exist only here. They are added to the real app, so each test goes through the
// app's own error handler.
describe("the error handler", () => {
  let t: Awaited<ReturnType<typeof createTestApp>>;
  let app: FastifyInstance;
  const logged = vi.fn();

  beforeAll(async () => {
    t = await createTestApp();
    app = t.app;

    app.withTypeProvider<ZodTypeProvider>().get(
      "/test/validated",
      { schema: { querystring: z.object({ n: z.coerce.number().int() }) } },
      async (request) => ({ n: request.query.n }),
    );
    app.post("/test/echo", async (request) => request.body);
    app.get("/test/database-refusal", async () => {
      throw dbError("23505", "Already registered in a lecture section of this course");
    });
    app.get("/test/unexpected", async (request) => {
      vi.spyOn(request.log, "error").mockImplementation(logged);
      throw new Error('relation "grade_entries" does not exist');
    });
  });

  afterAll(async () => {
    vi.restoreAllMocks();
    await t.close();
  });

  it("answers an unknown route with not_found", async () => {
    const r = await app.inject({ method: "GET", url: "/nowhere" });
    expect(r.statusCode).toBe(404);
    expect(r.json()).toEqual({ error: { code: "not_found", message: "Not found." } });
  });

  it("summarises a request that fails validation", async () => {
    const r = await app.inject({ method: "GET", url: "/test/validated?n=abc" });
    expect(r.statusCode).toBe(400);
    expect(r.json().error.code).toBe("invalid_request");
    expect(r.json().error.message).toContain("querystring/n");
  });

  it("rejects a malformed JSON body as invalid_request", async () => {
    const r = await app.inject({ method: "POST", url: "/test/echo", headers: { "content-type": "application/json" }, payload: "{" });
    expect(r.statusCode).toBe(400);
    expect(r.json().error.code).toBe("invalid_request");
  });

  it("maps a database refusal raised inside a route", async () => {
    const r = await app.inject({ method: "GET", url: "/test/database-refusal" });
    expect(r.statusCode).toBe(409);
    expect(r.json()).toEqual({
      error: { code: "conflict", message: "Already registered in a lecture section of this course" },
    });
  });

  it("logs an unexpected failure and tells the client nothing about it", async () => {
    const r = await app.inject({ method: "GET", url: "/test/unexpected" });
    expect(r.statusCode).toBe(500);
    expect(r.json()).toEqual({ error: { code: "internal", message: "Something went wrong. Please try again." } });
    expect(logged).toHaveBeenCalledWith(
      expect.objectContaining({ err: expect.objectContaining({ message: 'relation "grade_entries" does not exist' }) }),
      expect.any(String),
    );
  });
});
