import { PreviewPage } from "./PreviewPage.tsx";
import { sampleCourses } from "./sampleData.ts";

export function CoursesPreview() {
  return (
    <PreviewPage title="Courses">
      <div className="preview-grid">
        {sampleCourses.map((course) => (
          <article key={course.name} className="preview-card">
            <h2>{course.name}</h2>
            <p className="preview-muted">{course.teacher}</p>
            <progress value={course.progress} max={100} aria-label={`${course.name} progress`}>
              {course.progress}%
            </progress>
            <p className="preview-muted">{course.progress}% complete</p>
            <ul className="preview-list">
              {course.materials.map((material) => (
                <li key={material}>{material}</li>
              ))}
            </ul>
          </article>
        ))}
      </div>
    </PreviewPage>
  );
}
