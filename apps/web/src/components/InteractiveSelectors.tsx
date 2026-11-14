import { useId } from "react";
import { useLanguage } from "../lib/i18n.tsx";

export type AcademicYearId = "all" | "year-1" | "year-2" | "year-3" | "year-4";

export type AcademicYearOption = {
  id: AcademicYearId;
  badge: string;
  enTitle: string;
  arTitle: string;
  enMeta: string;
  arMeta: string;
  credits: string;
};

export const ACADEMIC_YEARS: AcademicYearOption[] = [
  {
    id: "all",
    badge: "ALL",
    enTitle: "All Academic Levels",
    arTitle: "جميع الفرق الدراسية",
    enMeta: "Full curriculum view",
    arMeta: "عرض جميع المقررات",
    credits: "136 Cr",
  },
  {
    id: "year-1",
    badge: "Y1",
    enTitle: "Level 1 · Freshman",
    arTitle: "الفرقة الأولى · تأسيسي",
    enMeta: "Foundation & Core Math",
    arMeta: "العلوم الأساسية والبرمجة",
    credits: "34 Cr",
  },
  {
    id: "year-2",
    badge: "Y2",
    enTitle: "Level 2 · Sophomore",
    arTitle: "الفرقة الثانية · تخصصي",
    enMeta: "Data Structures & Systems",
    arMeta: "هياكل البيانات والأنظمة",
    credits: "68 Cr",
  },
  {
    id: "year-3",
    badge: "Y3",
    enTitle: "Level 3 · Junior",
    arTitle: "الفرقة الثالثة · متقدم",
    enMeta: "AI & Software Architecture",
    arMeta: "الذكاء الاصطناعي وهندسة البرمجيات",
    credits: "102 Cr",
  },
  {
    id: "year-4",
    badge: "Y4",
    enTitle: "Level 4 · Senior Cohort",
    arTitle: "الفرقة الرابعة · مشروع التخرج",
    enMeta: "Graduation Project & Research",
    arMeta: "دفعة التخرج والمشاريع التطبيقية",
    credits: "136 Cr",
  },
];

export function AcademicYearStepper({
  value,
  onChange,
  label,
  useRadioLabels = false,
}: {
  value: AcademicYearId;
  onChange: (next: AcademicYearId) => void;
  label?: string;
  useRadioLabels?: boolean;
}) {
  const { t } = useLanguage();
  const groupName = useId();

  return (
    <div
      className="uf-year-stepper"
      role="group"
      aria-label={label ?? t("Academic year selector", "اختيار الفرقة الدراسية")}
    >
      <div className="uf-year-stepper-head">
        <span className="uf-kicker">{t("INTERACTIVE LEVEL SELECTOR", "اختيار المرحلة الدراسية التفاعلي")}</span>
        <span className="uf-year-hint">
          {t("Tap a card to switch academic level", "اضغط على البطاقة لتبديل الفرقة الدراسية")}
        </span>
      </div>
      <div className="uf-year-cards">
        {ACADEMIC_YEARS.map((year) => {
          const active = value === year.id;
          if (useRadioLabels) {
            return (
              <label
                key={year.id}
                className={active ? "uf-year-card active" : "uf-year-card"}
              >
                <input
                  type="radio"
                  name={groupName}
                  value={year.id}
                  checked={active}
                  onChange={() => onChange(year.id)}
                  className="sr-only-input"
                />
                <span className="uf-year-card-top">
                  <span className="uf-year-badge">{year.badge}</span>
                  <span className="uf-year-credits">{year.credits}</span>
                </span>
                <strong className="uf-year-title">{t(year.enTitle, year.arTitle)}</strong>
                <small className="uf-year-meta">{t(year.enMeta, year.arMeta)}</small>
              </label>
            );
          }

          return (
            <button
              key={year.id}
              type="button"
              aria-pressed={active}
              className={active ? "uf-year-card active" : "uf-year-card"}
              onClick={() => onChange(year.id)}
            >
              <span className="uf-year-card-top">
                <span className="uf-year-badge">{year.badge}</span>
                <span className="uf-year-credits">{year.credits}</span>
              </span>
              <strong className="uf-year-title">{t(year.enTitle, year.arTitle)}</strong>
              <small className="uf-year-meta">{t(year.enMeta, year.arMeta)}</small>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export type PillOption<T extends string> = {
  value: T;
  enLabel: string;
  arLabel: string;
  badge?: string;
};

export function SegmentedPillSelector<T extends string>({
  options,
  value,
  onChange,
  ariaLabel,
  useRadioLabels = false,
}: {
  options: PillOption<T>[];
  value: T;
  onChange: (next: T) => void;
  ariaLabel: string;
  useRadioLabels?: boolean;
}) {
  const { t } = useLanguage();
  const groupName = useId();

  return (
    <div className="uf-pill-selector" role="group" aria-label={ariaLabel}>
      {options.map((option) => {
        const active = option.value === value;
        if (useRadioLabels) {
          return (
            <label
              key={option.value}
              className={active ? "uf-pill-chip active" : "uf-pill-chip"}
            >
              <input
                type="radio"
                name={groupName}
                value={option.value}
                checked={active}
                onChange={() => onChange(option.value)}
                className="sr-only-input"
              />
              <span>{t(option.enLabel, option.arLabel)}</span>
              {option.badge && <b className="uf-pill-badge">{option.badge}</b>}
            </label>
          );
        }

        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={active}
            className={active ? "uf-pill-chip active" : "uf-pill-chip"}
            onClick={() => onChange(option.value)}
          >
            <span>{t(option.enLabel, option.arLabel)}</span>
            {option.badge && <b className="uf-pill-badge">{option.badge}</b>}
          </button>
        );
      })}
    </div>
  );
}
