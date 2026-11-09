import type { ReactNode } from "react";

export const PREVIEW_NOTE = "Preview: sample data. This part of Cohort isn't connected yet.";
export const DISABLED_NOTE = "Not available in the preview.";

export function PreviewPage({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="preview-page">
      <h1>{title}</h1>
      <p className="preview-banner" role="note">
        {PREVIEW_NOTE}
      </p>
      {children}
    </div>
  );
}
