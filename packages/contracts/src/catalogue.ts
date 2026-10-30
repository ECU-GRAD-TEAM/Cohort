import { z } from "zod";

export const Term = z.object({
  id: z.uuid(),
  code: z.string(),
  name: z.string(),
  startsOn: z.iso.date(),
  endsOn: z.iso.date(),
  registrationOpensAt: z.iso.datetime().nullable(),
  registrationClosesAt: z.iso.datetime().nullable(),
  addDropEndsAt: z.iso.datetime().nullable(),
});
export type Term = z.infer<typeof Term>;

export const TermsResponse = z.object({ terms: z.array(Term) });
export type TermsResponse = z.infer<typeof TermsResponse>;

export const TermParams = z.object({ termId: z.uuid() });
export type TermParams = z.infer<typeof TermParams>;

export const Meeting = z.object({
  weekday: z.int().min(1).max(7),
  startsAt: z.string().regex(/^\d{2}:\d{2}$/),
  endsAt: z.string().regex(/^\d{2}:\d{2}$/),
  room: z.string().nullable(),
});
export type Meeting = z.infer<typeof Meeting>;

export const CatalogueSection = z.object({
  id: z.uuid(),
  code: z.string(),
  kind: z.enum(["lecture", "lab", "tutorial"]),
  capacity: z.int().nullable(),
  course: z.object({
    id: z.uuid(),
    code: z.string(),
    title: z.string(),
    creditHours: z.number(),
  }),
  meetings: z.array(Meeting),
});
export type CatalogueSection = z.infer<typeof CatalogueSection>;

export const SectionsResponse = z.object({ sections: z.array(CatalogueSection) });
export type SectionsResponse = z.infer<typeof SectionsResponse>;
