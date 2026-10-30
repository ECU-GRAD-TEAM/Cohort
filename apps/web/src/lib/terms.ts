import type { Term } from "@cohort/contracts";

/**
 * Whether students can register in the term at `now`, as the database's `enroll_in_section`
 * decides it. A term is open from the moment registration opens until add/drop ends (or, with no
 * add/drop date, until registration closes), both inclusive. A term with an opening time and no end
 * stays open from its opening on. A term with no opening time is never open.
 */
function isRegistrationOpen(term: Term, now: Date): boolean {
  if (term.registrationOpensAt === null) return false;
  const time = now.getTime();
  if (time < Date.parse(term.registrationOpensAt)) return false;
  const end = term.addDropEndsAt ?? term.registrationClosesAt;
  return end === null || time <= Date.parse(end);
}

/** The term whose registration window contains `now`, else the first term, else nothing. */
export function pickDefaultTerm(terms: Term[], now: Date): Term | undefined {
  return terms.find((term) => isRegistrationOpen(term, now)) ?? terms[0];
}
