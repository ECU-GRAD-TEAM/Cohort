import type { CatalogueSection, Term } from "@cohort/contracts";
import { useQuery } from "@tanstack/react-query";
import { useId, useState, type ReactNode } from "react";
import { useApi } from "../lib/ApiContext.tsx";
import { formatCredits, formatMeeting } from "../lib/format.ts";
import { queryKeys } from "../lib/queryKeys.ts";
import { pickDefaultTerm } from "../lib/terms.ts";

function SectionRow({ section, assigned }: { section: CatalogueSection; assigned: boolean }) {
  return (
    <li>
      <p>{`${section.course.code} ${section.course.title} · Section ${section.code} · ${formatCredits(section.course.creditHours)}`}</p>
      {assigned && <p className="assigned">Your section</p>}
      {section.meetings.length > 0 && (
        <ul className="meeting-list">
          {section.meetings.map((meeting, index) => (
            <li key={index}>{formatMeeting(meeting)}</li>
          ))}
        </ul>
      )}
    </li>
  );
}

function SectionList({ termId }: { termId: string }) {
  const api = useApi();
  const sections = useQuery({ queryKey: queryKeys.sections(termId), queryFn: () => api.getSections(termId) });
  const enrollments = useQuery({ queryKey: queryKeys.enrollments, queryFn: () => api.getMyEnrollments() });

  // Which sections are marked as the student's depends on their enrolments, so nothing is listed
  // until both answers are in.
  const sectionsData = sections.data;
  const enrollmentsData = enrollments.data;
  if (sectionsData === undefined || enrollmentsData === undefined) {
    return (
      <>
        {(sections.isPending || enrollments.isPending) && <p>Loading…</p>}
        {sectionsData === undefined && sections.error && <p role="alert">{sections.error.message}</p>}
        {enrollmentsData === undefined && enrollments.error && <p role="alert">{enrollments.error.message}</p>}
      </>
    );
  }

  if (sectionsData.sections.length === 0) {
    return <p>No sections are published for this term yet.</p>;
  }

  const assignedSectionIds = new Set(
    enrollmentsData.enrollments
      .filter((enrollment) => enrollment.status === "enrolled" || enrollment.status === "waitlisted")
      .flatMap((enrollment) => enrollment.sections.map((section) => section.id)),
  );
  return (
    <ul className="card-list">
      {sectionsData.sections.map((section) => (
        <SectionRow key={section.id} section={section} assigned={assignedSectionIds.has(section.id)} />
      ))}
    </ul>
  );
}

function TermRegistration({ terms, defaultTerm }: { terms: Term[]; defaultTerm: Term }) {
  const selectId = useId();
  const [termId, setTermId] = useState(defaultTerm.id);

  return (
    <>
      <p className="field-row">
        <label htmlFor={selectId}>Term</label>
        <select id={selectId} value={termId} onChange={(event) => setTermId(event.target.value)}>
          {terms.map((term) => (
            <option key={term.id} value={term.id}>
              {term.name}
            </option>
          ))}
        </select>
      </p>
      <SectionList termId={termId} />
    </>
  );
}

export function RegistrationPage() {
  const api = useApi();
  const terms = useQuery({ queryKey: queryKeys.terms, queryFn: () => api.getTerms() });

  let content: ReactNode;
  if (terms.isPending) {
    content = <p>Loading…</p>;
  } else if (terms.data === undefined) {
    content = <p role="alert">{terms.error?.message}</p>;
  } else {
    // Only the first render of TermRegistration uses this; after that the student's choice stands.
    const defaultTerm = pickDefaultTerm(terms.data.terms, new Date());
    content =
      defaultTerm === undefined ? (
        <p>No terms are available.</p>
      ) : (
        <TermRegistration terms={terms.data.terms} defaultTerm={defaultTerm} />
      );
  }

  return (
    <>
      <h1>Course registration</h1>
      <p>
        Your registrar enrols you in courses and assigns your class meetings. Here are the term&rsquo;s
        sections and their times; yours are marked.
      </p>
      {content}
    </>
  );
}
