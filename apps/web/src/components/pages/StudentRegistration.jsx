import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { CalendarClock, CheckCircle2, ClipboardCheck, Loader2, Search } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { groupSectionsByCourse, isRegistrationOpen, pickDefaultTerm } from '../../lib/liveData';
import { ProfileHubNav } from '../profile/ProfileHubNav';

const DAYS_EN = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const DAYS_AR = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const KIND = {
  lecture: ['Lecture', 'محاضرة'],
  lab: ['Lab', 'معمل'],
  tutorial: ['Tutorial', 'سكشن'],
};

/** Loads something from the API, with loading and error states and a retry. */
function useLoad(load, deps) {
  const [state, setState] = useState({ status: 'loading' });
  const run = useCallback(async () => {
    setState({ status: 'loading' });
    try {
      setState({ status: 'ready', value: await load() });
    } catch (error) {
      setState({ status: 'error', error });
    }
  }, deps); // the caller lists what `load` depends on
  useEffect(() => {
    run();
  }, [run]);
  return { ...state, retry: run };
}

function formatDate(iso, lang) {
  if (!iso) return null;
  return new Date(iso).toLocaleDateString(lang === 'ar' ? 'ar-EG' : 'en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

/**
 * A student's registration: the term's published sections with their times, and the courses and
 * sections the registrar has enrolled them in. Students don't pick sections themselves.
 */
export function StudentRegistration() {
  const { t, lang, api } = useCohort();
  const terms = useLoad(() => api.terms(), [api]);
  const enrollments = useLoad(() => api.enrollments(), [api]);
  const [termId, setTermId] = useState('');

  useEffect(() => {
    if (terms.status === 'ready' && !termId) {
      setTermId(pickDefaultTerm(terms.value.terms)?.id ?? '');
    }
  }, [termId, terms]);

  const term = terms.status === 'ready' ? terms.value.terms.find((x) => x.id === termId) : undefined;
  const mine = useMemo(
    () =>
      enrollments.status === 'ready'
        ? enrollments.value.enrollments.filter(
            (e) => e.termId === termId && (e.status === 'enrolled' || e.status === 'waitlisted')
          )
        : [],
    [enrollments, termId]
  );
  const enrolledCredits = mine
    .filter((e) => e.status === 'enrolled')
    .reduce((sum, e) => sum + e.course.creditHours, 0);

  return (
    <section className="page-enter space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {t('COURSE REGISTRATION', 'تسجيل المقررات')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {t('Your registration', 'تسجيلك')}
          </h1>
          <p className="mt-1 max-w-2xl text-sm text-[#6E645D]">
            {t(
              "Your registrar enrols you in courses and assigns your lecture, lab and tutorial times. Here are the term's sections and their times; yours are marked.",
              'يسجلك المسجل في المقررات ويحدد مواعيد محاضراتك ومعاملك وسكاشنك. هذه شعب الفصل ومواعيدها، وشعبك مميزة.'
            )}
          </p>
        </div>
        {terms.status === 'ready' && terms.value.terms.length > 0 ? (
          <label className="flex items-center gap-2 text-xs font-semibold text-[#6E645D]">
            {t('Term', 'الفصل')}
            <select
              value={termId}
              onChange={(e) => setTermId(e.target.value)}
              className="min-h-[42px] rounded-xl border border-[#E8E3D9] bg-white px-3 text-xs font-bold text-[#302521]"
            >
              {terms.value.terms.map((x) => (
                <option key={x.id} value={x.id}>
                  {x.name}
                </option>
              ))}
            </select>
          </label>
        ) : null}
      </div>

      <ProfileHubNav />

      {terms.status === 'loading' ? <Loading t={t} /> : null}
      {terms.status === 'error' ? <LoadError t={t} error={terms.error} retry={terms.retry} /> : null}
      {terms.status === 'ready' && terms.value.terms.length === 0 ? (
        <Empty>{t('No terms have been published yet.', 'لم تُنشر أي فصول دراسية بعد.')}</Empty>
      ) : null}

      {term ? (
        <>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <Stat label={t('Courses enrolled', 'المقررات المسجلة')} value={mine.filter((e) => e.status === 'enrolled').length} />
            <Stat label={t('Credit hours', 'الساعات المعتمدة')} value={enrolledCredits} />
            <div className="cohort-card p-4 space-y-1.5">
              <div className="flex items-center gap-1.5 text-xs font-bold text-[#6E645D]">
                <CalendarClock className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                <span>{t('Registration window', 'فترة التسجيل')}</span>
              </div>
              <p className="text-sm font-bold text-[#302521]">
                {term.registrationOpensAt
                  ? `${formatDate(term.registrationOpensAt, lang)} – ${
                      formatDate(term.addDropEndsAt ?? term.registrationClosesAt, lang) ?? '…'
                    }`
                  : t('Not set yet', 'لم تُحدد بعد')}
              </p>
              <p className="text-[11px] font-semibold text-[#6E645D]">
                {isRegistrationOpen(term) ? t('Open now', 'مفتوحة الآن') : t('Closed', 'مغلقة')}
              </p>
            </div>
          </div>

          <MyEnrolments t={t} enrollments={enrollments} mine={mine} />
          <TermSections key={term.id} termId={term.id} mine={mine} />
        </>
      ) : null}
    </section>
  );
}

function MyEnrolments({ t, enrollments, mine }) {
  return (
    <div className="cohort-card p-6 space-y-3">
      <div className="flex items-center gap-2">
        <ClipboardCheck className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
        <h2 className="text-base font-bold text-[#302521]">{t('Your courses this term', 'مقرراتك هذا الفصل')}</h2>
      </div>
      {enrollments.status === 'loading' ? <Loading t={t} /> : null}
      {enrollments.status === 'error' ? (
        <LoadError t={t} error={enrollments.error} retry={enrollments.retry} />
      ) : null}
      {enrollments.status === 'ready' && mine.length === 0 ? (
        <p className="text-xs text-[#6E645D]">
          {t(
            "You aren't enrolled in any course this term yet. Your registrar enrols you; contact them if something is missing.",
            'لم يتم تسجيلك في أي مقرر هذا الفصل بعد. المسجل هو من يسجلك؛ تواصل معه إذا كان هناك نقص.'
          )}
        </p>
      ) : null}
      <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2">
        {mine.map((e) => (
          <div key={e.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
            <div className="flex items-start justify-between gap-2">
              <p className="text-sm font-bold text-[#302521]">
                {e.course.code} · {e.course.title}
              </p>
              <span
                className={`shrink-0 rounded-md px-2 py-0.5 text-[10px] font-bold ${
                  e.status === 'enrolled' ? 'bg-[#E8F5EC] text-[#16845B]' : 'bg-[#FFF4D4] text-[#80540D]'
                }`}
              >
                {e.status === 'enrolled'
                  ? t('Enrolled', 'مسجل')
                  : t(`Waitlist #${e.waitlistPosition}`, `قائمة الانتظار #${e.waitlistPosition}`)}
              </span>
            </div>
            <p className="mt-1 text-xs text-[#6E645D]">
              {e.course.creditHours} {t('credit hours', 'ساعات معتمدة')} ·{' '}
              {e.sections.length
                ? `${t('Sections', 'الشعب')} ${e.sections.map((s) => s.code).join(', ')}`
                : t('Class times not assigned yet', 'لم تُحدد مواعيد المحاضرات بعد')}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

function TermSections({ termId, mine }) {
  const { t, lang, api } = useCohort();
  const sections = useLoad(() => api.sections(termId), [api, termId]);
  const [query, setQuery] = useState('');
  const assigned = useMemo(() => new Set(mine.flatMap((e) => e.sections.map((s) => s.id))), [mine]);

  const groups = useMemo(() => {
    if (sections.status !== 'ready') return [];
    const q = query.trim().toLowerCase();
    return groupSectionsByCourse(sections.value.sections).filter(
      (g) => !q || g.code.toLowerCase().includes(q) || g.title.toLowerCase().includes(q)
    );
  }, [query, sections]);

  const days = lang === 'ar' ? DAYS_AR : DAYS_EN;

  return (
    <div className="cohort-card p-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-base font-bold text-[#302521]">{t("This term's sections", 'شعب هذا الفصل')}</h2>
        <label className="relative w-full sm:w-64">
          <span className="sr-only">{t('Search courses', 'ابحث في المقررات')}</span>
          <Search className="pointer-events-none absolute start-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#6E645D]" aria-hidden="true" />
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('Search by code or title', 'ابحث بالرمز أو الاسم')}
            className="w-full rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] py-2 pe-3 ps-9 text-xs text-[#302521]"
          />
        </label>
      </div>

      {sections.status === 'loading' ? <Loading t={t} /> : null}
      {sections.status === 'error' ? <LoadError t={t} error={sections.error} retry={sections.retry} /> : null}
      {sections.status === 'ready' && sections.value.sections.length === 0 ? (
        <Empty>{t('No sections are published for this term yet.', 'لم تُنشر أي شعب لهذا الفصل بعد.')}</Empty>
      ) : null}
      {sections.status === 'ready' && sections.value.sections.length > 0 && groups.length === 0 ? (
        <Empty>{t('No course matches your search.', 'لا يوجد مقرر يطابق بحثك.')}</Empty>
      ) : null}

      <div className="space-y-3">
        {groups.map((g) => (
          <div key={g.code} className="overflow-hidden rounded-2xl border border-[#E8E3D9] bg-white">
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[#E8E3D9] px-4 py-3">
              <p className="text-sm font-bold text-[#302521]">
                {g.code} · {g.title}
              </p>
              <span className="text-xs font-semibold text-[#6E645D] tabular-nums">
                {g.creditHours} {t('credit hours', 'ساعات معتمدة')}
              </span>
            </div>
            <ul className="divide-y divide-[#E8E3D9]">
              {g.sections.map((s) => {
                const yours = assigned.has(s.id);
                return (
                  <li
                    key={s.id}
                    className={`flex flex-col gap-1.5 px-4 py-3 sm:flex-row sm:items-center sm:justify-between ${
                      yours ? 'bg-[#FFF9E4]' : ''
                    }`}
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-md border border-[#E8E3D9] bg-[#FCFBF6] px-2 py-0.5 text-[10px] font-bold uppercase text-[#302521]">
                        {t(...KIND[s.kind])}
                      </span>
                      <span className="text-xs font-bold text-[#302521]">
                        {t('Section', 'الشعبة')} {s.code}
                      </span>
                      {s.capacity != null ? (
                        <span className="text-[11px] text-[#6E645D]">
                          · {s.capacity} {t('seats', 'مقعد')}
                        </span>
                      ) : null}
                      {yours ? (
                        <span className="inline-flex items-center gap-1 rounded-md bg-[#B81104] px-2 py-0.5 text-[10px] font-bold text-[#FFFACD]">
                          <CheckCircle2 className="h-3 w-3" aria-hidden="true" />
                          {t('Your section', 'شعبتك')}
                        </span>
                      ) : null}
                    </div>
                    <div className="flex flex-wrap gap-x-3 gap-y-1 text-[11px] font-semibold text-[#6E645D] tabular-nums">
                      {s.meetings.length === 0 ? <span>{t('Times to be announced', 'المواعيد لم تُعلن بعد')}</span> : null}
                      {s.meetings.map((m, i) => (
                        <span key={i}>
                          {days[m.weekday - 1]} {m.startsAt}–{m.endsAt}
                          {m.room ? ` · ${m.room}` : ''}
                        </span>
                      ))}
                    </div>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </div>
    </div>
  );
}

function Stat({ label, value }) {
  return (
    <div className="cohort-card p-4 space-y-1.5">
      <span className="text-xs font-bold text-[#6E645D]">{label}</span>
      <p className="text-2xl font-extrabold text-[#302521] tabular-nums">{value}</p>
    </div>
  );
}

function Loading({ t }) {
  return (
    <p role="status" className="flex items-center gap-2 text-xs font-semibold text-[#6E645D]">
      <Loader2 className="h-4 w-4 animate-spin text-[#B81104]" aria-hidden="true" />
      {t('Loading…', 'جارٍ التحميل…')}
    </p>
  );
}

function LoadError({ t, error, retry }) {
  return (
    <div role="alert" className="rounded-xl border border-[#C93636]/30 bg-[#FFE9E5] p-3.5 text-xs text-[#8A1F1F]">
      <p>{error.message}</p>
      <button type="button" onClick={retry} className="mt-2 font-bold underline">
        {t('Try again', 'حاول مرة أخرى')}
      </button>
    </div>
  );
}

function Empty({ children }) {
  return (
    <p className="rounded-xl border border-dashed border-[#E8E3D9] bg-[#FCFBF6] p-4 text-center text-xs text-[#6E645D]">
      {children}
    </p>
  );
}
