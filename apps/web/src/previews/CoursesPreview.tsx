import { useState } from "react";
import { Link } from "react-router";
import { Icon } from "../components/Icons.tsx";
import {
  AcademicYearStepper,
  type AcademicYearId,
} from "../components/InteractiveSelectors.tsx";
import { useLanguage } from "../lib/i18n.tsx";
import { PreviewPage } from "./PreviewPage.tsx";
import { sampleCourses } from "./sampleData.ts";

export function CoursesPreview() {
  const { t } = useLanguage();
  const [selectedYear, setSelectedYear] = useState<AcademicYearId>("all");

  return (
    <PreviewPage title="Courses">
      <AcademicYearStepper
        value={selectedYear}
        onChange={setSelectedYear}
        label={t("Filter courses by academic year", "تصفية المقررات حسب الفرقة الدراسية")}
      />

      <div className="preview-grid uf-courses-showcase">
        {sampleCourses.map((course, idx) => (
          <article key={course.name} className="preview-card uf-course-showcase-card">
            <div className={`uf-course-cover uf-cover-${idx % 2}`}>
              <span>{t("ACADEMIC COURSE", "مقرر جامعي")}</span>
              <b>{`0${idx + 1}`}</b>
            </div>
            <div className="uf-course-showcase-body">
              <h2>{course.name}</h2>
              <p className="preview-muted">{course.teacher}</p>
              <progress
                value={course.progress}
                max={100}
                aria-label={`${course.name} progress`}
              >
                {course.progress}%
              </progress>
              <p className="preview-muted">{course.progress}% complete</p>
              <ul className="preview-list">
                {course.materials.map((material) => (
                  <li key={material} className="uf-material-row">
                    <Icon name="file" size={14} />
                    <span>{material}</span>
                  </li>
                ))}
              </ul>
              <div className="uf-student-course-links">
                <Link to="/student-assistant">
                  <Icon name="spark" size={13} />
                  <span>{t("Ask AI Assistant", "اسأل المساعد الذكي")}</span>
                </Link>
                <Link to="/messages">
                  <Icon name="chat" size={13} />
                  <span>{t("Course Group", "جروب المقرر")}</span>
                </Link>
              </div>
            </div>
          </article>
        ))}
      </div>
    </PreviewPage>
  );
}
