import React from 'react';
import { Info, Loader2 } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';

// What each page shows: 'live' pages read the university's records, 'mixed' pages combine them with
// sample sections, 'preview' pages are sample data only. Pages not listed need no notice.
const PAGE_NOTES = {
  dashboard: {
    kind: 'mixed',
    en: 'Your courses and timetable are live. Deadlines, appointments and announcements are sample data for now.',
    ar: 'مقرراتك وجدولك بيانات حقيقية. المواعيد النهائية والحجوزات والإعلانات بيانات تجريبية حاليًا.',
  },
  courses: {
    kind: 'mixed',
    en: 'Your courses, sections, teachers and published grades are live. Materials, assignments, quizzes, attendance and discussions are sample data for now.',
    ar: 'مقرراتك وشعبك ومحاضروك ودرجاتك المنشورة بيانات حقيقية. المواد والتكليفات والاختبارات والحضور والنقاشات بيانات تجريبية حاليًا.',
  },
  schedule: {
    kind: 'mixed',
    en: 'Your weekly classes are live. The month calendar of deadlines and appointments is sample data for now.',
    ar: 'محاضراتك الأسبوعية بيانات حقيقية. تقويم الشهر للمواعيد النهائية والحجوزات بيانات تجريبية حاليًا.',
  },
  assistant: {
    kind: 'mixed',
    en: 'General and course questions go to the Cohort assistant. Answers in the Materials, Assignments, Exams and People modes are sample data for now.',
    ar: 'الأسئلة العامة وأسئلة المقررات تذهب إلى مساعد Cohort. إجابات أوضاع المواد والتكليفات والاختبارات والأشخاص بيانات تجريبية حاليًا.',
  },
  profile: {
    kind: 'mixed',
    en: 'Your name, email and university come from your account. Other details you add are saved on this device only.',
    ar: 'اسمك وبريدك وجامعتك من حسابك. التفاصيل الأخرى التي تضيفها تُحفظ على هذا الجهاز فقط.',
  },
  'academic-affairs': { kind: 'preview' },
  grading: { kind: 'preview' },
  messages: { kind: 'preview' },
  map: { kind: 'preview' },
  notifications: { kind: 'preview' },
  support: { kind: 'preview' },
};
// Advisor approvals are still sample data; a student's registration page is live.
const STAFF_NOTES = { registration: { kind: 'preview' } };

const PREVIEW_TEXT = {
  en: "Preview: this page shows sample data and isn't connected to your university yet. Nothing you do here is sent anywhere.",
  ar: 'معاينة: تعرض هذه الصفحة بيانات تجريبية وليست مرتبطة بجامعتك بعد. لا يُرسل أي شيء تفعله هنا.',
};

/** A one-line notice above the page saying what is real and what is sample data. */
export function PageNotice() {
  const { page, role, t, live } = useCohort();
  const note = (role === 'Academic Staff' && STAFF_NOTES[page]) || PAGE_NOTES[page];
  const usesLive = ['dashboard', 'courses', 'schedule'].includes(page);

  return (
    <>
      {usesLive && live.status === 'error' ? (
        <div role="alert" className="mb-4 flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-[#C93636]/30 bg-[#FFE9E5] px-4 py-2.5 text-xs text-[#8A1F1F]">
          <span>
            {t('Your courses and timetable could not be loaded.', 'تعذّر تحميل مقرراتك وجدولك.')} {live.error?.message}
          </span>
          <button type="button" onClick={live.reload} className="font-bold underline">
            {t('Try again', 'حاول مرة أخرى')}
          </button>
        </div>
      ) : null}
      {usesLive && live.status === 'loading' ? (
        <p role="status" className="mb-4 flex items-center gap-2 text-xs font-semibold text-[#6E645D]">
          <Loader2 className="h-3.5 w-3.5 animate-spin text-[#B81104]" aria-hidden="true" />
          {t('Loading your courses and timetable…', 'جارٍ تحميل مقرراتك وجدولك…')}
        </p>
      ) : null}
      {note ? (
        <div
          className={`mb-4 flex items-start gap-2 rounded-2xl border px-4 py-2.5 text-xs ${
            note.kind === 'preview'
              ? 'border-[#E9DBA9] bg-[#FFF4D4] text-[#5C3D09]'
              : 'border-[#E8E3D9] bg-white text-[#6E645D]'
          }`}
        >
          <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-[#B81104]" aria-hidden="true" />
          <span>{note.kind === 'preview' ? t(PREVIEW_TEXT.en, PREVIEW_TEXT.ar) : t(note.en, note.ar)}</span>
        </div>
      ) : null}
    </>
  );
}
