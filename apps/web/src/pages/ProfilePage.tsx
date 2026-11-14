import { useQuery } from "@tanstack/react-query";
import { Icon } from "../components/Icons.tsx";
import { useApi } from "../lib/ApiContext.tsx";
import { formatRole, initials } from "../lib/format.ts";
import { translateRoleLabel, useLanguage } from "../lib/i18n.tsx";
import { queryKeys } from "../lib/queryKeys.ts";

export function ProfilePage() {
  const api = useApi();
  const { lang, t } = useLanguage();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });

  const user = me.data;
  const displayName = user?.displayName ?? "Student";
  const personalEmail = user?.email ?? "student@university.edu";
  const universityName = user?.tenant.name ?? "University";
  const roleLabel = user ? translateRoleLabel(formatRole(user), lang) : t("Student", "طالب");
  const isTa = user?.roles.includes("teaching_assistant") ?? false;

  const academicYearValue = isTa
    ? t("Academic Teaching Staff · Level 1–4 Sections", "هيئة معاونة · الفرق الأولى حتى الرابعة")
    : t("Year 4 · Senior Cohort (Level 4)", "الفرقة الرابعة · دفعة التخرج (المستوى الرابع)");

  const phoneValue = "+20 100 245 8910";
  const advisorName = "Dr. Leila Hassan";
  const advisorEmail = "dr.leila.hassan@ecu.edu.eg";

  return (
    <div className="uf-dashboard uf-profile-page" aria-label={t("Student Profile", "الملف الشخصي")}>
      <div className="uf-heading">
        <div>
          <span className="uf-kicker">
            {t("UNIFLOW / OFFICIAL ACADEMIC RECORD", "بوابة الجامعة · السجل الأكاديمي الرسمي")}
          </span>
          <h1>{t("Academic Profile", "الملف الشخصي الأكاديمي")}</h1>
          <p>
            {t(
              "Verified university directory information. Records on this page are read-only and managed by the registrar.",
              "بياناتك الجامعية المعتمدة لدى شؤون الطلاب. هذه الصفحة للعرض فقط ولا يمكن تعديلها يدوياً.",
            )}
          </p>
        </div>
        <span className="uf-demo uf-readonly-badge">
          <Icon name="lock" size={14} />
          <span>{t("Read-only record", "سجل رسمي للعرض فقط")}</span>
        </span>
      </div>

      <section className="uf-panel uf-profile-hero-card">
        <div className="uf-profile-identity">
          <span className="uf-profile-avatar" aria-hidden="true">
            {initials(displayName)}
          </span>
          <div>
            <span className="uf-kicker">{universityName}</span>
            <h2>{displayName}</h2>
            <div className="uf-profile-tags">
              <span className="uf-course-code-pill">{roleLabel}</span>
              <span className="uf-course-credits-pill">
                {t("Status: Active", "الحالة: مقيد ونشط")}
              </span>
            </div>
          </div>
        </div>
      </section>

      <div className="uf-profile-grid">
        <article className="uf-panel uf-profile-field-card">
          <div className="uf-profile-field-icon">
            <Icon name="mail" size={20} />
          </div>
          <div className="uf-profile-field-body">
            <span className="uf-kicker">{t("PERSONAL EMAIL", "البريد الإلكتروني الشخصي")}</span>
            <h3>{t("Personal Email", "البريد الإلكتروني الشخصي")}</h3>
            <p className="uf-profile-value" data-testid="profile-personal-email">
              {personalEmail}
            </p>
            <small>{t("Primary university & personal identity address", "البريد المعتمد للتواصل الجامعي")}</small>
          </div>
        </article>

        <article className="uf-panel uf-profile-field-card">
          <div className="uf-profile-field-icon">
            <Icon name="award" size={20} />
          </div>
          <div className="uf-profile-field-body">
            <span className="uf-kicker">{t("ACADEMIC PROGRESSION", "المرحلة الدراسية")}</span>
            <h3>{t("Academic Year", "السنة الدراسية")}</h3>
            <p className="uf-profile-value" data-testid="profile-academic-year">
              {academicYearValue}
            </p>
            <small>{t("Software Engineering & Computer Science", "قسم هندسة البرمجيات وعلوم الحاسب")}</small>
          </div>
        </article>

        <article className="uf-panel uf-profile-field-card">
          <div className="uf-profile-field-icon">
            <Icon name="phone" size={20} />
          </div>
          <div className="uf-profile-field-body">
            <span className="uf-kicker">{t("CONTACT INFORMATION", "بيانات الاتصال")}</span>
            <h3>{t("Contact Information", "معلومات التواصل")}</h3>
            <p className="uf-profile-value" data-testid="profile-contact-info" dir="ltr">
              {phoneValue}
            </p>
            <small>{t("Verified mobile phone & emergency contact", "رقم الهاتف المسجل لدى شؤون الطلاب")}</small>
          </div>
        </article>

        <article className="uf-panel uf-profile-field-card uf-advisor-card">
          <div className="uf-profile-field-icon">
            <Icon name="user" size={20} />
          </div>
          <div className="uf-profile-field-body">
            <span className="uf-kicker">{t("ACADEMIC ADVISING", "الإرشاد الأكاديمي")}</span>
            <h3>{t("Academic Advisor's Email", "بريد المرشد الأكاديمي")}</h3>
            <p className="uf-advisor-name">{advisorName}</p>
            <a
              href={`mailto:${advisorEmail}?subject=Academic%20Advising%20Inquiry`}
              className="uf-advisor-mailto"
              aria-label={`Email Academic Advisor at ${advisorEmail}`}
            >
              <Icon name="mail" size={16} />
              <span>{advisorEmail}</span>
              <Icon name="arrowUpRight" size={14} />
            </a>
            <small>
              {t(
                "Click the email address above to open Outlook and draft a message to your advisor.",
                "اضغط على البريد الإلكتروني لفتح برنامج Outlook وإرسال رسالة مباشرة للمرشد الأكاديمي.",
              )}
            </small>
          </div>
        </article>
      </div>
    </div>
  );
}
