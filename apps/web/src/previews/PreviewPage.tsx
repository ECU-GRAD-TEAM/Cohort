import type { ReactNode } from "react";
import { Link } from "react-router";
import { Icon } from "../components/Icons.tsx";
import { translateNavLabel, useLanguage } from "../lib/i18n.tsx";

export const PREVIEW_NOTE = "Preview: sample data. This part of Cohort isn't connected yet.";
export const DISABLED_NOTE = "Not available in the preview.";

export function PreviewPage({ title, children }: { title: string; children: ReactNode }) {
  const { lang, t } = useLanguage();
  return (
    <div className="preview-page uf-dashboard">
      <div className="uf-heading">
        <div>
          <span className="uf-kicker">
            {t("COHORT / ACADEMIC WORKSPACE", "بوابة الجامعة الذكية · المساحة الأكاديمية")}
          </span>
          <h1>{translateNavLabel(title, lang)}</h1>
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
      <p className="preview-banner" role="note">
        {PREVIEW_NOTE}
      </p>
      {children}
    </div>
  );
}
