import { createContext, useContext, useEffect, useState, type ReactNode } from "react";

export type AppLanguage = "en" | "ar";

type LanguageContextValue = {
  lang: AppLanguage;
  isRtl: boolean;
  setLang: (lang: AppLanguage) => void;
  toggleLang: () => void;
  t: (en: string, ar: string) => string;
};

const LanguageContext = createContext<LanguageContextValue>({
  lang: "en",
  isRtl: false,
  setLang: () => {},
  toggleLang: () => {},
  t: (en) => en,
});

const NAV_TRANSLATIONS: Record<string, string> = {
  Dashboard: "لوحة التحكم",
  Registration: "التسجيل الأكاديمي",
  "AI Assistant": "المساعد الذكي",
  "Student assistant": "المساعد الذكي",
  Courses: "المقررات الدراسية",
  Schedule: "الجدول الدراسي",
  Assignments: "التكليفات والمهام",
  Messages: "جروبات التواصل",
  Support: "الدعم الأكاديمي",
  Campus: "الحرم الجامعي",
};

const ROLE_TRANSLATIONS: Record<string, string> = {
  Student: "طالب جامعي",
  "Teaching Assistant": "معيد / هيئة معاونة",
  Staff: "هيئة تدريس / موظف",
  "Non-staff": "حساب جامعي",
};

export function translateNavLabel(label: string, lang: AppLanguage): string {
  if (lang === "en") return label;
  return NAV_TRANSLATIONS[label] ?? label;
}

export function translateRoleLabel(role: string, lang: AppLanguage): string {
  if (lang === "en") return role;
  return ROLE_TRANSLATIONS[role] ?? role;
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [lang, setLang] = useState<AppLanguage>("en");
  const isRtl = lang === "ar";

  useEffect(() => {
    if (typeof document !== "undefined") {
      document.documentElement.lang = lang;
      document.documentElement.dir = isRtl ? "rtl" : "ltr";
    }
  }, [lang, isRtl]);

  const toggleLang = () => {
    setLang((current) => (current === "en" ? "ar" : "en"));
  };

  const t = (en: string, ar: string) => (lang === "ar" ? ar : en);

  return (
    <LanguageContext.Provider value={{ lang, isRtl, setLang, toggleLang, t }}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage(): LanguageContextValue {
  return useContext(LanguageContext);
}
