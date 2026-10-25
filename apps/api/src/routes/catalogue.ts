import { SectionsResponse, TermParams, TermsResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { ApiError } from "../errors.ts";
import { toClockTime, toIsoDate, toNumber } from "../format.ts";

/** Contracts carry timestamps in the `Z` form that `toISOString` produces. */
const toIsoTimestamp = (d: Date | null) => d?.toISOString() ?? null;

export const catalogueRoutes: FastifyPluginAsync = async (app) => {
  const api = app.withTypeProvider<ZodTypeProvider>();

  api.get("/terms", { schema: { response: { 200: TermsResponse } } }, async (request) => {
    // Row-level security leaves only the caller's university, so there is no tenant filter here.
    const terms = await request.withDb((tx) =>
      tx.terms.findMany({ orderBy: [{ starts_on: "desc" }, { code: "asc" }] }),
    );
    return {
      terms: terms.map((term) => ({
        id: term.id,
        code: term.code,
        name: term.name,
        startsOn: toIsoDate(term.starts_on),
        endsOn: toIsoDate(term.ends_on),
        registrationOpensAt: toIsoTimestamp(term.registration_opens_at),
        registrationClosesAt: toIsoTimestamp(term.registration_closes_at),
        addDropEndsAt: toIsoTimestamp(term.add_drop_ends_at),
      })),
    };
  });

  api.get(
    "/terms/:termId/sections",
    { schema: { params: TermParams, response: { 200: SectionsResponse } } },
    async (request) => {
      const { termId } = request.params;
      const found = await request.withDb(async (tx) => {
        // Another university's term is invisible to the caller, so it reads as unknown.
        const term = await tx.terms.findUnique({ where: { id: termId }, select: { id: true } });
        if (!term) return null;

        // One query at a time: a transaction has a single connection (see `withDb`). The
        // meetings are therefore a second query rather than a second relation on the first.
        const published = { course_offerings: { term_id: termId, status: "published" as const } };
        const sections = await tx.sections.findMany({
          where: published,
          orderBy: [{ course_offerings: { courses: { code: "asc" } } }, { code: "asc" }],
          select: {
            id: true,
            code: true,
            kind: true,
            capacity: true,
            course_offerings: {
              select: { courses: { select: { id: true, code: true, title: true, credit_hours: true } } },
            },
          },
        });
        const entries = await tx.timetable_entries.findMany({
          where: { sections: published },
          orderBy: [{ weekday: "asc" }, { starts_at: "asc" }, { ends_at: "asc" }],
          select: {
            section_id: true,
            weekday: true,
            starts_at: true,
            ends_at: true,
            rooms: { select: { code: true } },
          },
        });
        return { sections, entries };
      });
      if (!found) throw new ApiError(404, "not_found", "Term not found.");

      const meetingsBySection = new Map<string, SectionsResponse["sections"][number]["meetings"]>();
      for (const entry of found.entries) {
        const meetings = meetingsBySection.get(entry.section_id) ?? [];
        meetings.push({
          weekday: entry.weekday,
          startsAt: toClockTime(entry.starts_at),
          endsAt: toClockTime(entry.ends_at),
          room: entry.rooms?.code ?? null,
        });
        meetingsBySection.set(entry.section_id, meetings);
      }

      return {
        sections: found.sections.map((section) => {
          const course = section.course_offerings.courses;
          return {
            id: section.id,
            code: section.code,
            kind: section.kind,
            capacity: section.capacity,
            course: {
              id: course.id,
              code: course.code,
              title: course.title,
              creditHours: toNumber(course.credit_hours),
            },
            meetings: meetingsBySection.get(section.id) ?? [],
          };
        }),
      };
    },
  );
};
