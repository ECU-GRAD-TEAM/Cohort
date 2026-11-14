import { useState } from "react";
import {
  AcademicYearStepper,
  SegmentedPillSelector,
  type AcademicYearId,
} from "../components/InteractiveSelectors.tsx";
import { useLanguage } from "../lib/i18n.tsx";
import { PreviewPage } from "./PreviewPage.tsx";
import { sampleAssignments } from "./sampleData.ts";

export function AssignmentsPreview() {
  const { t } = useLanguage();
  const [selectedYear, setSelectedYear] = useState<AcademicYearId>("all");
  const [filter, setFilter] = useState<"all" | "active" | "submitted">("all");

  return (
    <PreviewPage title="Assignments">
      <AcademicYearStepper
        value={selectedYear}
        onChange={setSelectedYear}
        label={t("Filter assignments by academic year", "تصفية التكليفات حسب الفرقة الدراسية")}
      />

      <div className="uf-track-bar">
        <span className="uf-kicker">{t("ASSESSMENT STATUS", "حالة التكليفات والامتحانات")}</span>
        <SegmentedPillSelector
          ariaLabel={t("Filter assignments by status", "تصفية حسب الحالة")}
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", enLabel: "All Assessments", arLabel: "جميع التكليفات", badge: "4" },
            { value: "active", enLabel: "In Progress & Upcoming", arLabel: "جاري وقادم" },
            { value: "submitted", enLabel: "Submitted", arLabel: "تم التسليم" },
          ]}
        />
      </div>

      <ul className="preview-list preview-cards uf-assignment-grid">
        {sampleAssignments.map((item) => (
          <li key={item.title} className="preview-card uf-assignment-card">
            <div className="uf-assignment-top">
              <span className="uf-course-code-pill">{item.course}</span>
              <span className="status-pill">{item.status}</span>
            </div>
            <h2>{item.title}</h2>
            <p className="preview-muted">
              {item.course} · {item.due}
            </p>
          </li>
        ))}
      </ul>
    </PreviewPage>
  );
}
