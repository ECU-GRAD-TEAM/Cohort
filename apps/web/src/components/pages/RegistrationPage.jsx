import React, { useMemo, useState } from 'react';
import {
  AlertCircle,
  BookCheck,
  CheckCheck,
  CheckCircle2,
  ClipboardCheck,
  Clock,
  PlusCircle,
  Trash2,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { COURSE_CATALOG } from '../../data/seedData';
import { validateCourseRegistration } from '../../utils/validation';
import { ProfileHubNav } from '../profile/ProfileHubNav';
import { StatusBadge } from '../common/StatusBadge';
import { StudentRegistration } from './StudentRegistration';

const COMPLETED_PREREQS = ['CS101', 'CS201', 'CS320'];

export function RegistrationPage() {
  const { role } = useCohort();
  return role === 'Academic Staff' ? <AdviseeRegistration /> : <StudentRegistration />;
}

// Advisor approvals and rosters: still sample data (shown with a Preview notice).
function AdviseeRegistration() {
  const { role, lang, t, profile, data, setData, showToast } = useCohort();
  const isStaff = role === 'Academic Staff';

  const [selectedCode, setSelectedCode] = useState(COURSE_CATALOG[2].code);
  const [errorMsg, setErrorMsg] = useState('');
  const [staffStatusFilter, setStaffStatusFilter] = useState('All');

  const offering = COURSE_CATALOG.find((c) => c.code === selectedCode) || COURSE_CATALOG[0];
  const [lectureId, setLectureId] = useState(offering.lectures[0]?.id || '');
  const [labId, setLabId] = useState(offering.labs[0]?.id || '');
  const [sectionId, setSectionId] = useState(offering.sections[0]?.id || '');

  const handleCourseSelect = (code) => {
    setSelectedCode(code);
    const next = COURSE_CATALOG.find((c) => c.code === code);
    setLectureId(next?.lectures[0]?.id || '');
    setLabId(next?.labs[0]?.id || '');
    setSectionId(next?.sections[0]?.id || '');
    setErrorMsg('');
  };

  const activeRegistrations = useMemo(
    () => data.registrations.filter((r) => r.status !== 'Withdrawn' && r.status !== 'Rejected'),
    [data.registrations]
  );

  const totalCredits = useMemo(
    () => activeRegistrations.reduce((sum, r) => sum + (Number(r.credits) || 3), 0),
    [activeRegistrations]
  );

  const selectedSlots = useMemo(() => {
    const lec = offering.lectures.find((x) => x.id === lectureId);
    const lab = offering.labs.find((x) => x.id === labId);
    const sec = offering.sections.find((x) => x.id === sectionId);
    return [lec, lab, sec].filter(Boolean).map((s) => ({
      courseCode: offering.code,
      type: s.label.split(' · ')[0],
      day: s.day,
      start: s.start,
      end: s.end,
      label: s.label,
    }));
  }, [labId, lectureId, offering, sectionId]);

  const liveConflictMessage = useMemo(
    () =>
      validateCourseRegistration({
        offering,
        selectedSlots,
        existingRegistrations: data.registrations,
        completedPrerequisites: COMPLETED_PREREQS,
      }),
    [data.registrations, offering, selectedSlots]
  );

  const handleRegister = (e) => {
    e.preventDefault();
    const lec = offering.lectures.find((x) => x.id === lectureId);
    const lab = offering.labs.find((x) => x.id === labId);
    const sec = offering.sections.find((x) => x.id === sectionId);

    const validationError = validateCourseRegistration({
      offering,
      selectedSlots,
      existingRegistrations: data.registrations,
      completedPrerequisites: COMPLETED_PREREQS,
    });

    if (validationError) {
      setErrorMsg(validationError);
      return;
    }

    setErrorMsg('');
    setData((prev) => ({
      ...prev,
      registrations: [
        ...prev.registrations,
        {
          id: `reg-${Date.now()}`,
          studentName: profile.name,
          studentNameAr: profile.nameAr || profile.name,
          studentId: profile.id,
          courseCode: offering.code,
          courseName: offering.name,
          courseNameAr: offering.nameAr,
          credits: offering.credits,
          lecture: lec?.label || '—',
          lab: lab?.label || t('No Lab', 'لا يوجد معمل'),
          section: sec?.label || '—',
          status: 'Pending Advisor',
          slots: selectedSlots,
        },
      ],
    }));
    showToast(t(`${offering.code} added to registration.`, `تمت إضافة ${offering.code} للتسجيل.`));
  };

  const removeRegistration = (id) => {
    setData((prev) => ({
      ...prev,
      registrations: prev.registrations.filter((r) => r.id !== id),
    }));
    showToast(t('Course removed from registration.', 'تم حذف المقرر من التسجيل.'));
  };

  const approveRegistration = (id, nextStatus) => {
    setData((prev) => ({
      ...prev,
      registrations: prev.registrations.map((r) => (r.id === id ? { ...r, status: nextStatus } : r)),
    }));
    showToast(t(`Registration ${nextStatus}.`, `تم تحديث التسجيل إلى ${nextStatus}.`));
  };

  const handleApproveAllPending = () => {
    const pendingCount = data.registrations.filter((r) => r.status === 'Pending Advisor').length;
    if (!pendingCount) {
      showToast(t('No pending registrations to approve.', 'لا توجد تسجيلات معلقة للاعتماد.'));
      return;
    }
    setData((prev) => ({
      ...prev,
      registrations: prev.registrations.map((r) =>
        r.status === 'Pending Advisor' ? { ...r, status: 'Approved' } : r
      ),
    }));
    showToast(
      t(
        `Approved ${pendingCount} pending course registration(s).`,
        `تم اعتماد ${pendingCount} تسجيلات معلقة.`
      )
    );
  };

  const visibleRegistrations = useMemo(() => {
    if (!isStaff || staffStatusFilter === 'All') return data.registrations;
    return data.registrations.filter((r) => r.status === staffStatusFilter);
  }, [data.registrations, isStaff, staffStatusFilter]);

  const loadPercent = Math.min(100, Math.round((activeRegistrations.length / 7) * 100));
  const prereqSatisfied =
    !offering.prerequisite || COMPLETED_PREREQS.includes(offering.prerequisite);

  return (
    <section className="page-enter space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {t('COURSE REGISTRATION · MAX 7 COURSES', 'تسجيل المقررات · بحد أقصى ٧ مقررات')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {isStaff
              ? t('Advisee Registration Approvals & Sections', 'اعتماد تسجيل الطلاب والشُعب')
              : t('Course Registration (Lecture / Lab / Section)', 'تسجيل المقررات (محاضرة / معمل / سكشن)')}
          </h1>
        </div>
        <div className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD] px-4 py-2 text-xs font-bold text-[#B81104] tabular-nums">
          {activeRegistrations.length} / 7 {t('Courses Registered', 'مقررات مسجلة')} · {totalCredits}/21 Cr
        </div>
      </div>

      <ProfileHubNav />

      {/* Registration Load & Prerequisite Summary Bar */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="cohort-card p-4 space-y-2">
          <div className="flex items-center justify-between text-xs font-bold text-[#6E645D]">
            <span>{t('Course Load Cap', 'الحد الأقصى للمقررات')}</span>
            <span className="text-[#B81104] tabular-nums">{activeRegistrations.length} / 7 Max</span>
          </div>
          <div className="h-2.5 w-full rounded-full bg-[#EFECE5] overflow-hidden">
            <div className="h-full rounded-full bg-[#B81104]" style={{ width: `${loadPercent}%` }} />
          </div>
        </div>

        <div className="cohort-card p-4 space-y-2">
          <div className="flex items-center justify-between text-xs font-bold text-[#6E645D]">
            <span>{t('Credit Hours Registered', 'الساعات المعتمدة المسجلة')}</span>
            <span className="text-[#302521] tabular-nums">{totalCredits} / 21 Cr Max</span>
          </div>
          <div className="h-2.5 w-full rounded-full bg-[#EFECE5] overflow-hidden">
            <div
              className="h-full rounded-full bg-[#16845B]"
              style={{ width: `${Math.min(100, Math.round((totalCredits / 21) * 100))}%` }}
            />
          </div>
        </div>

        <div className="cohort-card p-4 space-y-1.5">
          <div className="flex items-center gap-1.5 text-xs font-bold text-[#6E645D]">
            <BookCheck className="h-4 w-4 text-[#16845B]" aria-hidden="true" />
            <span>{t('Completed Prerequisites', 'المتطلبات السابقة المكتملة')}</span>
          </div>
          <div className="flex flex-wrap gap-1.5 pt-0.5">
            {COMPLETED_PREREQS.map((code) => (
              <span
                key={code}
                className="rounded-md bg-[#E8F5EC] px-2 py-0.5 text-[11px] font-bold text-[#16845B]"
              >
                {code} ✓
              </span>
            ))}
          </div>
        </div>
      </div>

      {!isStaff ? (
        <form onSubmit={handleRegister} className="cohort-card p-6 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <ClipboardCheck className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
              <h2 className="text-base font-bold text-[#302521]">
                {t('Add Course with Lecture, Lab & Section', 'إضافة مقرر مع اختيار المحاضرة والمعمل والسكشن')}
              </h2>
            </div>

            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className="font-semibold text-[#6E645D]">
                {t('Lecturer:', 'المحاضر:')} <strong className="text-[#302521]">{offering.lecturer}</strong>
              </span>
              {offering.prerequisite ? (
                <span
                  className={`rounded-lg px-2.5 py-1 text-[11px] font-bold ${
                    prereqSatisfied
                      ? 'bg-[#E8F5EC] text-[#16845B]'
                      : 'bg-[#FFE9E5] text-[#9E1C0E]'
                  }`}
                >
                  {t('Prerequisite:', 'المتطلب:')} {offering.prerequisite}{' '}
                  {prereqSatisfied ? t('✓ Completed', '✓ مكتمل') : t('Missing', 'غير مكتمل')}
                </span>
              ) : (
                <span className="rounded-lg bg-[#FCFBF6] border border-[#E8E3D9] px-2.5 py-1 text-[11px] font-semibold text-[#6E645D]">
                  {t('No Prerequisite Required', 'لا يوجد متطلب سابق')}
                </span>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label htmlFor="reg-course" className="block text-xs font-semibold text-[#302521] mb-1">
                {t('Course', 'المقرر')}
              </label>
              <select
                id="reg-course"
                value={selectedCode}
                onChange={(e) => handleCourseSelect(e.target.value)}
                className="w-full min-h-[42px] rounded-xl border border-[#D6CFC1] bg-white px-3 text-xs font-semibold text-[#302521]"
              >
                {COURSE_CATALOG.map((c) => (
                  <option key={c.code} value={c.code}>
                    {c.code} · {lang === 'ar' ? c.nameAr : c.name} ({c.credits} Cr)
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label htmlFor="reg-lecture" className="block text-xs font-semibold text-[#302521] mb-1">
                {t('Lecture Group', 'مجموعة المحاضرة')}
              </label>
              <select
                id="reg-lecture"
                value={lectureId}
                onChange={(e) => setLectureId(e.target.value)}
                className="w-full min-h-[42px] rounded-xl border border-[#D6CFC1] bg-white px-3 text-xs text-[#302521]"
              >
                {offering.lectures.map((l) => (
                  <option key={l.id} value={l.id}>
                    {l.label}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label htmlFor="reg-lab" className="block text-xs font-semibold text-[#302521] mb-1">
                {t('Lab Session', 'المعمل')}
              </label>
              <select
                id="reg-lab"
                value={labId}
                onChange={(e) => setLabId(e.target.value)}
                disabled={offering.labs.length === 0}
                className="w-full min-h-[42px] rounded-xl border border-[#D6CFC1] bg-white px-3 text-xs text-[#302521] disabled:bg-[#F2F0EB]"
              >
                {offering.labs.length === 0 ? (
                  <option value="">{t('No Lab Required', 'لا يوجد معمل لهذا المقرر')}</option>
                ) : (
                  offering.labs.map((l) => (
                    <option key={l.id} value={l.id}>
                      {l.label}
                    </option>
                  ))
                )}
              </select>
            </div>

            <div>
              <label htmlFor="reg-section" className="block text-xs font-semibold text-[#302521] mb-1">
                {t('Tutorial Section', 'السكشن')}
              </label>
              <select
                id="reg-section"
                value={sectionId}
                onChange={(e) => setSectionId(e.target.value)}
                className="w-full min-h-[42px] rounded-xl border border-[#D6CFC1] bg-white px-3 text-xs text-[#302521]"
              >
                {offering.sections.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.label}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Live Selected Slots Preview */}
          <div className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5 space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
              <span className="inline-flex items-center gap-1.5 font-bold text-[#302521]">
                <Clock className="h-3.5 w-3.5 text-[#B81104]" aria-hidden="true" />
                <span>{t('Selected Component Slots Preview', 'معاينة مواعيد المكونات المختارة')}</span>
              </span>
              {liveConflictMessage ? (
                <span className="inline-flex items-center gap-1 text-[11px] font-bold text-[#9E1C0E]">
                  <AlertCircle className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{liveConflictMessage}</span>
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 text-[11px] font-bold text-[#16845B]">
                  <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('No schedule clash detected', 'لا يوجد تعارض في المواعيد')}</span>
                </span>
              )}
            </div>
            <div className="flex flex-wrap gap-2">
              {selectedSlots.map((slot) => (
                <span
                  key={slot.label}
                  className="rounded-lg border border-[#E8E3D9] bg-white px-2.5 py-1 text-[11px] font-semibold text-[#302521]"
                >
                  {slot.label}
                </span>
              ))}
            </div>
          </div>

          {errorMsg ? (
            <div
              role="alert"
              className="flex items-center gap-2 rounded-xl border border-[#C93636]/30 bg-[#FFE9E5] px-4 py-3 text-xs font-semibold text-[#9E1C0E]"
            >
              <AlertCircle className="h-4 w-4 shrink-0" aria-hidden="true" />
              <span>{errorMsg}</span>
            </div>
          ) : null}

          <button
            type="submit"
            className="inline-flex min-h-[42px] items-center gap-2 rounded-xl bg-[#B81104] px-5 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
          >
            <PlusCircle className="h-4 w-4" aria-hidden="true" />
            <span>{t('Register Course', 'تسجيل المقرر')}</span>
          </button>
        </form>
      ) : null}

      <div className="cohort-card p-6 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-base font-bold text-[#302521]">
            {isStaff
              ? t('Student Course Registration Queue', 'قائمة طلبات تسجيل الطلاب')
              : t('Current Registered Schedule', 'المقررات المسجلة حاليًا')}
          </h2>

          {isStaff ? (
            <div className="flex flex-wrap items-center gap-2">
              {[
                { id: 'All', label: t('All', 'الكل') },
                { id: 'Pending Advisor', label: t('Pending Advisor', 'بانتظار المرشد') },
                { id: 'Approved', label: t('Approved', 'معتمد') },
                { id: 'Rejected', label: t('Rejected', 'مرفوض') },
              ].map((st) => (
                <button
                  key={st.id}
                  type="button"
                  onClick={() => setStaffStatusFilter(st.id)}
                  className={`rounded-full border px-3 py-1 text-[11px] font-bold transition ${
                    staffStatusFilter === st.id
                      ? 'border-[#B81104] bg-[#FFFACD] text-[#B81104]'
                      : 'border-[#E8E3D9] bg-white text-[#6E645D]'
                  }`}
                >
                  {st.label}
                </button>
              ))}
              <button
                type="button"
                onClick={handleApproveAllPending}
                className="inline-flex items-center gap-1.5 rounded-xl bg-[#16845B] px-3.5 py-1.5 text-xs font-bold text-white hover:opacity-95"
              >
                <CheckCheck className="h-3.5 w-3.5" aria-hidden="true" />
                <span>{t('Approve All Pending', 'اعتماد الكل')}</span>
              </button>
            </div>
          ) : null}
        </div>

        <div className="divide-y divide-[#E8E3D9]">
          {visibleRegistrations.length === 0 ? (
            <p className="py-6 text-center text-xs text-[#6E645D]">
              {t('No registration entries in this filter.', 'لا توجد مقررات ضمن هذا التصنيف.')}
            </p>
          ) : (
            visibleRegistrations.map((reg) => (
              <div
                key={reg.id}
                className="flex flex-col justify-between gap-3 py-4 first:pt-1 last:pb-1 sm:flex-row sm:items-center"
              >
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded bg-[#B81104] px-2 py-0.5 text-[11px] font-bold text-[#FFFACD]">
                      {reg.courseCode}
                    </span>
                    <h3 className="text-sm font-bold text-[#302521]">
                      {lang === 'ar' && reg.courseNameAr ? reg.courseNameAr : reg.courseName}
                    </h3>
                    <span className="text-[11px] font-semibold text-[#6E645D] tabular-nums">
                      ({reg.credits || 3} {t('Cr', 'ساعة')})
                    </span>
                    <StatusBadge status={reg.status} />
                    {isStaff && reg.studentName ? (
                      <span className="rounded-md bg-[#FCFBF6] border border-[#E8E3D9] px-2 py-0.5 text-[11px] font-semibold text-[#302521]">
                        {lang === 'ar' && reg.studentNameAr ? reg.studentNameAr : reg.studentName}
                        {reg.studentId ? ` · ${reg.studentId}` : ''}
                      </span>
                    ) : null}
                  </div>
                  <p className="mt-1 text-xs text-[#6E645D]">
                    {reg.lecture} · {reg.lab} · {reg.section}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  {isStaff ? (
                    <>
                      <button
                        type="button"
                        onClick={() => approveRegistration(reg.id, 'Approved')}
                        className="rounded-lg bg-[#16845B] px-3 py-1.5 text-xs font-bold text-white"
                      >
                        {t('Approve', 'اعتماد')}
                      </button>
                      <button
                        type="button"
                        onClick={() => approveRegistration(reg.id, 'Rejected')}
                        className="rounded-lg border border-[#C93636]/40 px-3 py-1.5 text-xs font-bold text-[#C93636]"
                      >
                        {t('Reject', 'رفض')}
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      onClick={() => removeRegistration(reg.id)}
                      className="inline-flex items-center gap-1 rounded-lg border border-[#E8E3D9] px-3 py-1.5 text-xs font-semibold text-[#C93636] hover:bg-[#FFE9E5]"
                    >
                      <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                      <span>{t('Drop', 'حذف')}</span>
                    </button>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </section>
  );
}
