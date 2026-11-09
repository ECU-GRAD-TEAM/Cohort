import { PreviewPage } from "./PreviewPage.tsx";
import { sampleAssignments } from "./sampleData.ts";

export function AssignmentsPreview() {
  return (
    <PreviewPage title="Assignments">
      <ul className="preview-list preview-cards">
        {sampleAssignments.map((item) => (
          <li key={item.title} className="preview-card">
            <h2>{item.title}</h2>
            <p className="preview-muted">
              {item.course} · {item.due}
            </p>
            <span className="status-pill">{item.status}</span>
          </li>
        ))}
      </ul>
    </PreviewPage>
  );
}
