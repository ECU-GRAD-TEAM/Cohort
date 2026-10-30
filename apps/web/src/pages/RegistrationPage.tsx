import type { CatalogueSection, EnrollmentChange, Term } from "@cohort/contracts";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState, type ReactNode } from "react";
import { useApi } from "../lib/ApiContext.tsx";
import { formatCredits, formatMeeting } from "../lib/format.ts";
import { queryKeys } from "../lib/queryKeys.ts";
import { pickDefaultTerm } from "../lib/terms.ts";

type Action = "register" | "drop";
type Notice = { kind: "status" | "alert"; text: string };
type OnNotice = (notice: Notice | null) => void;

function successMessage(action: Action, name: string, change: EnrollmentChange): string {
  if (action === "drop") return `Dropped ${name}.`;
  const { status, waitlistPosition } = change.enrollment;
  if (status !== "waitlisted") return `Registered for ${name}.`;
  return waitlistPosition === null
    ? `Added to the waiting list for ${name}.`
    : `Added to the waiting list for ${name} (position ${waitlistPosition}).`;
}

function SectionRow({ section, held, onNotice }: { section: CatalogueSection; held: boolean; onNotice: OnNotice }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const name = `${section.course.code} ${section.code}`;

  const change = useMutation({
    mutationFn: (action: Action) => (action === "drop" ? api.drop(section.id) : api.enroll(section.id)),
    // Returning the refetch keeps the button disabled until the list shows the new state.
    onSuccess: (result, action) => {
      onNotice({ kind: "status", text: successMessage(action, name, result) });
      return queryClient.invalidateQueries({ queryKey: queryKeys.enrollments });
    },
    // The database's own reason is shown as it is; nothing else changes.
    onError: (error) => onNotice({ kind: "alert", text: error.message }),
  });

  return (
    <li>
      <p>{`${section.course.code} ${section.course.title} · Section ${section.code} · ${formatCredits(section.course.creditHours)}`}</p>
      {section.meetings.length > 0 && (
        <ul>
          {section.meetings.map((meeting, index) => (
            <li key={index}>{formatMeeting(meeting)}</li>
          ))}
        </ul>
      )}
      <button
        type="button"
        disabled={change.isPending}
        onClick={() => {
          onNotice(null);
          change.mutate(held ? "drop" : "register");
        }}
      >
        {held ? `Drop ${name}` : `Register for ${name}`}
      </button>
    </li>
  );
}

function SectionList({ termId, onNotice }: { termId: string; onNotice: OnNotice }) {
  const api = useApi();
  const sections = useQuery({ queryKey: queryKeys.sections(termId), queryFn: () => api.getSections(termId) });
  const enrollments = useQuery({ queryKey: queryKeys.enrollments, queryFn: () => api.getMyEnrollments() });

  // Which button a section gets depends on the student's enrolments, so nothing is listed until both
  // answers are in.
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
    return <p>No sections are open for registration in this term.</p>;
  }

  const heldSectionIds = new Set(
    enrollmentsData.enrollments
      .filter((enrollment) => enrollment.status === "enrolled" || enrollment.status === "waitlisted")
      .map((enrollment) => enrollment.sectionId),
  );
  return (
    <ul>
      {sectionsData.sections.map((section) => (
        <SectionRow key={section.id} section={section} held={heldSectionIds.has(section.id)} onNotice={onNotice} />
      ))}
    </ul>
  );
}

function TermRegistration({ terms, defaultTerm }: { terms: Term[]; defaultTerm: Term }) {
  const selectId = useId();
  const [termId, setTermId] = useState(defaultTerm.id);
  const [notice, setNotice] = useState<Notice | null>(null);

  return (
    <>
      <p>
        <label htmlFor={selectId}>Term</label>{" "}
        <select id={selectId} value={termId} onChange={(event) => setTermId(event.target.value)}>
          {terms.map((term) => (
            <option key={term.id} value={term.id}>
              {term.name}
            </option>
          ))}
        </select>
      </p>
      {notice?.kind === "status" && <p role="status">{notice.text}</p>}
      {notice?.kind === "alert" && <p role="alert">{notice.text}</p>}
      <SectionList termId={termId} onNotice={setNotice} />
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
      {content}
    </>
  );
}
