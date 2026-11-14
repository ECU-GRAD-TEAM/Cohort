import type { CatalogueSection, Term } from "@cohort/contracts";
import { useQuery } from "@tanstack/react-query";
import { useId, useState, type ReactNode } from "react";
import { Link } from "react-router";
import { Icon } from "../components/Icons.tsx";
import {
  AcademicYearStepper,
  type AcademicYearId,
} from "../components/InteractiveSelectors.tsx";
import { useApi } from "../lib/ApiContext.tsx";
import { formatCredits, formatMeeting } from "../lib/format.ts";
import { useLanguage } from "../lib/i18n.tsx";
import { queryKeys } from "../lib/queryKeys.ts";
import { pickDefaultTerm } from "../lib/terms.ts";

function SectionRow({ section, assigned }: { section: CatalogueSection; assigned: boolean }) {
  const { t } = useLanguage();
  return (
    <li className={assigned ? "uf-reg-card assigned-card" : "uf-reg-card"}>
      <div className="uf-reg-card-top">
        <span className="uf-course-code-pill">{section.course.code}</span>
        <span className="uf-section-kind-pill">{section.kind}</span>
        {section.capacity !== null && (
          <span className="uf-capacity-pill">
            <Icon name="users" size={13} />
            <span>
              {section.capacity} {t("seats", "مقعد")}
            </span>
          </span>
        )}
      </div>
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
  const sections = useQuery({
    queryKey: queryKeys.sections(termId),
    queryFn: () => api.getSections(termId),
  });
  const enrollments = useQuery({
    queryKey: queryKeys.enrollments,
    queryFn: () => api.getMyEnrollments(),
  });

  // Which sections are marked as the student's depends on their enrolments, so nothing is listed
  // until both answers are in.
  const sectionsData = sections.data;
  const enrollmentsData = enrollments.data;
  if (sectionsData === undefined || enrollmentsData === undefined) {
    return (
      <>
        {(sections.isPending || enrollments.isPending) && <p>Loading…</p>}
        {sectionsData === undefined && sections.error && (
          <p role="alert">{sections.error.message}</p>
        )}
        {enrollmentsData === undefined && enrollments.error && (
          <p role="alert">{enrollments.error.message}</p>
        )}
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
    <ul className="card-list uf-reg-grid">
      {sectionsData.sections.map((section) => (
        <SectionRow
          key={section.id}
          section={section}
          assigned={assignedSectionIds.has(section.id)}
        />
      ))}
    </ul>
  );
}

function TermRegistration({ terms, defaultTerm }: { terms: Term[]; defaultTerm: Term }) {
  const selectId = useId();
  const termRadioGroup = useId();
  const { t } = useLanguage();
  const [termId, setTermId] = useState(defaultTerm.id);
  const [selectedYear, setSelectedYear] = useState<AcademicYearId>("all");

  return (
    <>
      <AcademicYearStepper
        value={selectedYear}
        onChange={setSelectedYear}
        useRadioLabels={true}
        label={t("Academic year level view", "عرض الفرقة الدراسية")}
      />

      <div
        className="uf-term-deck"
        role="group"
        aria-label={t("Interactive term cards", "بطاقات الفصول الدراسية التفاعلية")}
      >
        <div className="uf-year-stepper-head">
          <span className="uf-kicker">
            {t("ACADEMIC TERM TIMELINE", "الفصول الدراسية المتاحة")}
          </span>
          <span className="uf-year-hint">
            {t(
              "Select a semester card to inspect its sections",
              "اختر بطاقة الفصل الدراسي لعرض السكاشن والمواعيد",
            )}
          </span>
        </div>
        <div className="uf-term-cards-row">
          {terms.map((term) => {
            const active = term.id === termId;
            return (
              <label
                key={term.id}
                className={active ? "uf-term-card active" : "uf-term-card"}
              >
                <input
                  type="radio"
                  name={termRadioGroup}
                  value={term.id}
                  checked={active}
                  onChange={() => setTermId(term.id)}
                  className="sr-only-input"
                />
                <span className="uf-term-card-top">
                  <span className="uf-term-code">{term.code}</span>
                  <span className="uf-term-dot" aria-hidden="true">
                    <Icon name="calendar" size={14} />
                  </span>
                </span>
                <strong>{term.name}</strong>
                <small>{`${term.startsOn} – ${term.endsOn}`}</small>
              </label>
            );
          })}
        </div>
      </div>

      <p className="field-row uf-synced-term-select">
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
  const { t } = useLanguage();
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
    <div className="uf-dashboard uf-registration-page">
      <div className="uf-heading">
        <div>
          <span className="uf-kicker">
            {t("COHORT / ACADEMIC REGISTRAR", "بوابة الجامعة الذكية · التسجيل والسكاشن")}
          </span>
          <h1>{t("Course registration", "Course registration")}</h1>
          <p>
            Your registrar enrols you in courses and assigns your class meetings. Here are the
            term&rsquo;s sections and their times; yours are marked.
          </p>
        </div>
        <div className="uf-heading-badges">
          <Link to="/student-assistant" className="uf-ai-pill-link">
            <Icon name="spark" size={14} />
            <span>{t("AI Assistant", "المساعد الذكي")}</span>
          </Link>
          <Link to="/messages" className="uf-demo">
            <Icon name="chat" size={14} />
            <span>{t("Course Groups", "جروبات المقررات")}</span>
          </Link>
        </div>
      </div>
      {content}
    </div>
  );
}
