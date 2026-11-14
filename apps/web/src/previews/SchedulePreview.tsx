import { useState } from "react";
import {
  AcademicYearStepper,
  SegmentedPillSelector,
  type AcademicYearId,
} from "../components/InteractiveSelectors.tsx";
import { useLanguage } from "../lib/i18n.tsx";
import { PreviewPage } from "./PreviewPage.tsx";
import { sampleLessons, weekDays } from "./sampleData.ts";

export function SchedulePreview() {
  const { t } = useLanguage();
  const [selectedYear, setSelectedYear] = useState<AcademicYearId>("all");
  const [sessionKind, setSessionKind] = useState<"all" | "lectures" | "labs">("all");

  return (
    <PreviewPage title="Schedule">
      <AcademicYearStepper
        value={selectedYear}
        onChange={setSelectedYear}
        label={t("Select academic year timetable", "اختر جدول الفرقة الدراسية")}
      />

      <div className="uf-track-bar">
        <span className="uf-kicker">{t("SESSION VIEW", "نوع الجلسات الدراسية")}</span>
        <SegmentedPillSelector
          ariaLabel={t("Filter schedule sessions", "تصفية الجدول الدراسي")}
          value={sessionKind}
          onChange={setSessionKind}
          options={[
            { value: "all", enLabel: "All Sessions", arLabel: "كل المواعيد" },
            { value: "lectures", enLabel: "Lectures", arLabel: "المحاضرات" },
            { value: "labs", enLabel: "TA Labs & Tutorials", arLabel: "السكاشن والمعامل" },
          ]}
        />
      </div>

      <div
        className="preview-timetable-scroll"
        role="region"
        aria-label="Weekly timetable"
        tabIndex={0}
      >
        <div className="preview-timetable">
          {weekDays.map((day) => (
            <section key={day} className="timetable-day" aria-label={day}>
              <h2>{day}</h2>
              {sampleLessons
                .filter((lesson) => lesson.day === day)
                .map((lesson) => (
                  <div
                    key={lesson.time + lesson.title}
                    className="timetable-slot"
                  >
                    <strong>{lesson.time}</strong> {lesson.title}
                    <span className="preview-muted">{lesson.room}</span>
                  </div>
                ))}
            </section>
          ))}
        </div>
      </div>
    </PreviewPage>
  );
}
