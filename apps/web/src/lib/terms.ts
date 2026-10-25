import type { Term } from "@cohort/contracts";

/**
 * Whether students can register in the term at `now`. A term is open from the moment registration
 * opens until add/drop ends (or, with no add/drop date, until registration closes), both inclusive.
 * A term missing its opening or its end is never open.
 */
function isRegistrationOpen(term: Term, now: Date): boolean {
  const end = term.addDropEndsAt ?? term.registrationClosesAt;
  if (term.registrationOpensAt === null || end === null) return false;
  const time = now.getTime();
  return Date.parse(term.registrationOpensAt) <= time && time <= Date.parse(end);
}

/** The term whose registration window contains `now`, else the first term, else nothing. */
export function pickDefaultTerm(terms: Term[], now: Date): Term | undefined {
  return terms.find((term) => isRegistrationOpen(term, now)) ?? terms[0];
}
