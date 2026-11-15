import React, { useMemo, useState } from 'react';
import {
  TrendingUp,
  Award,
  CheckCircle2,
  AlertTriangle,
  MessageSquare,
  Calculator,
  BookOpen,
  FileText,
  Users,
  Send,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { ProfileHubNav } from '../profile/ProfileHubNav';
import { StatusBadge } from '../common/StatusBadge';
import {
  DIRECTORY_PEOPLE,
  STUDENT_GPA_HISTORY,
  TOPIC_MASTERY_DATA,
} from '../../data/seedData';

export function AcademicAffairsPage() {
  const {
    role,
    lang,
    t,
    data,
    navigate,
    addPetition,
    updatePetitionStatus,
  } = useCohort();

  // What-If Grade Calculator state (Student)
  const [courseworkScore, setCourseworkScore] = useState(88);
  const [expectedFinal, setExpectedFinal] = useState(90);

  // Petition modal / inline form state (Student)
  const [petitionType, setPetitionType] = useState('Course Overload / Schedule Adjustment');
  const [petitionDetail, setPetitionDetail] = useState('');

  const projectedScore = useMemo(
    () => (Number(courseworkScore) * 0.6 + Number(expectedFinal) * 0.4).toFixed(1),
    [courseworkScore, expectedFinal]
  );

  const projectedGpa = useMemo(() => {
    const score = Number(projectedScore);
    if (score >= 93) return '3.92';
    if (score >= 88) return '3.85';
    if (score >= 80) return '3.72';
    return '3.55';
  }, [projectedScore]);

  const handlePetitionSubmit = (e) => {
    e.preventDefault();
    if (!petitionDetail.trim()) return;
    addPetition({
      type: petitionType,
      typeAr: petitionType,
      detail: petitionDetail.trim(),
    });
    setPetitionDetail('');
  };

  const advisor = DIRECTORY_PEOPLE.find((p) => p.isAdvisor);
  const advisees = DIRECTORY_PEOPLE.filter((p) => p.category === 'Student');

  if (role === 'Academic Staff') {
    const pendingReviews = data.gradeReviews.filter((g) => g.status !== 'Published').length;
    const draftCount = data.gradeReviews.filter((g) => g.status === 'Draft' || g.status === 'Needs review').length;
    const approvedCount = data.gradeReviews.filter((g) => g.status === 'Approved').length;
    const publishedCount = data.gradeReviews.filter((g) => g.status === 'Published').length;

    return (
      <section className="page-enter space-y-6">
        <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
          <div>
            <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
              {t('ACADEMIC AFFAIRS · FACULTY ANALYTICS', 'الشؤون الأكاديمية · تحليلات هيئة التدريس')}
            </p>
            <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
              {t('Academic Affairs & Cohort Analytics', 'الشؤون الأكاديمية وتحليلات الدفعة')}
            </h1>
            <p className="mt-1 text-sm text-[#6E645D]">
              {t(
                'Monitor section-level mastery, student attendance thresholds, grade publication pipeline, and advisee petitions.',
                'تابع إتقان المقررات عبر الشُعب، ومؤشرات الحضور، وحالة نشر الدرجات، والتماسات الطلاب المرشدين.'
              )}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => navigate('registration')}
              className="min-h-[42px] rounded-xl border border-[#E8E3D9] bg-white px-4 py-2 text-xs font-bold text-[#302521] hover:border-[#B81104] hover:text-[#B81104]"
            >
              {t('Advisee Course Approvals', 'اعتماد تسجيل الطلاب')}
            </button>
            <button
              type="button"
              onClick={() => navigate('grading')}
              className="min-h-[42px] rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
            >
              {t('Open Gradebook & Builder', 'فتح سجل الدرجات')}
            </button>
          </div>
        </div>

        <ProfileHubNav />

        {/* Faculty KPIs */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <div className="cohort-card p-5">
            <span className="text-xs font-semibold text-[#6E645D]">
              {t('Enrolled Students', 'إجمالي الطلاب المسجلين')}
            </span>
            <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">128</p>
            <p className="mt-1 text-xs text-[#16845B] font-semibold">
              {t('Across 3 active sections', 'عبر ٣ شُعب نشطة')}
            </p>
          </div>

          <div className="cohort-card p-5">
            <span className="text-xs font-semibold text-[#6E645D]">
              {t('Cohort Mastery Average', 'متوسط إتقان الدفعة')}
            </span>
            <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">82.4%</p>
            <p className="mt-1 text-xs text-[#B76E00] font-semibold">
              {t('Recursion flagged at 58%', 'الاستدعاء الذاتي يحتاج دعمًا (٥٨٪)')}
            </p>
          </div>

          <div className="cohort-card p-5">
            <span className="text-xs font-semibold text-[#6E645D]">
              {t('Pending Grade Reviews', 'تقييمات بانتظار المراجعة')}
            </span>
            <p className="mt-2 text-3xl font-extrabold text-[#B81104] tabular-nums">{pendingReviews}</p>
            <p className="mt-1 text-xs text-[#6E645D]">
              {t(`${draftCount} Draft · ${approvedCount} Approved · ${publishedCount} Published`, `${draftCount} مسودة · ${approvedCount} معتمد · ${publishedCount} منشور`)}
            </p>
          </div>

          <div className="cohort-card p-5">
            <span className="text-xs font-semibold text-[#6E645D]">
              {t('Advisee Petitions', 'التماسات الإرشاد الأكاديمي')}
            </span>
            <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">
              {data.petitions.length}
            </p>
            <p className="mt-1 text-xs text-[#B81104] font-semibold">
              {t('Advisor review required', 'يتطلب قرار المرشد الأكاديمي')}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
          {/* Topic Mastery Heatmap */}
          <div className="cohort-card p-6 lg:col-span-7 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h2 className="text-base font-bold text-[#302521]">
                  {t('Topic Mastery Heatmap by Section', 'خريطة إتقان الموضوعات حسب الشعبة')}
                </h2>
                <p className="text-xs text-[#6E645D]">
                  {t('Share of correct assessment items tagged per topic', 'نسبة الإجابات الصحيحة حسب كل موضوع')}
                </p>
              </div>
              <button
                type="button"
                onClick={() => navigate('assistant')}
                className="rounded-lg bg-[#FFFACD] px-3 py-1.5 text-xs font-bold text-[#B81104] hover:bg-[#FFF2B5]"
              >
                {t('Draft Revision Quiz with AI', 'إنشاء مراجعة بالمساعد الذكي')}
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-start text-xs">
                <thead>
                  <tr className="border-b border-[#E8E3D9] text-[#6E645D]">
                    <th className="py-2.5 pe-3 font-semibold text-start">{t('Topic', 'الموضوع')}</th>
                    <th className="px-2 py-2.5 font-semibold text-center">{t('Sec A', 'شعبة أ')}</th>
                    <th className="px-2 py-2.5 font-semibold text-center">{t('Sec B', 'شعبة ب')}</th>
                    <th className="px-2 py-2.5 font-semibold text-center">{t('Sec C', 'شعبة ج')}</th>
                    <th className="ps-2 py-2.5 font-semibold text-end">{t('Status', 'الحالة')}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[#E8E3D9]">
                  {TOPIC_MASTERY_DATA.map((row) => {
                    const avg = Math.round((row.secA + row.secB + row.secC) / 3);
                    const state = avg >= 80 ? 'Mastered' : avg >= 65 ? 'Developing' : 'Needs Intervention';
                    return (
                      <tr key={row.topic}>
                        <td className="py-3 pe-3">
                          <span className="block font-semibold text-[#302521]">
                            {lang === 'ar' ? row.topicAr : row.topic}
                          </span>
                          <span className="text-[11px] text-[#6E645D]">
                            {row.course} · n={row.n}
                          </span>
                        </td>
                        {[row.secA, row.secB, row.secC].map((val, i) => (
                          <td key={i} className="px-1.5 py-2 text-center tabular-nums">
                            <span
                              className={`inline-block min-w-[46px] rounded-md px-2 py-1 font-bold ${
                                val >= 80
                                  ? 'bg-[#E8F5EC] text-[#16845B]'
                                  : val >= 65
                                    ? 'bg-[#FFFACD] text-[#80540D]'
                                    : 'bg-[#FFE9E5] text-[#9E1C0E]'
                              }`}
                            >
                              {val}%
                            </span>
                          </td>
                        ))}
                        <td className="ps-2 py-2 text-end">
                          <StatusBadge status={state} />
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>

          {/* Advisee & Attendance Watchlist */}
          <div className="cohort-card p-6 lg:col-span-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-bold text-[#302521]">
                {t('Advisees & Attendance Threshold (85%)', 'الطلاب المرشدون وحد الحضور (٨٥٪)')}
              </h2>
              <Users className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
            </div>

            <div className="space-y-3">
              {advisees.map((st) => {
                const lowAttendance = (st.attendance || 0) < 85;
                return (
                  <div
                    key={st.id}
                    className={`flex items-center justify-between gap-3 rounded-xl border p-3.5 ${
                      lowAttendance
                        ? 'border-[#C93636]/30 bg-[#FFE9E5]/40'
                        : 'border-[#E8E3D9] bg-[#FCFBF6]'
                    }`}
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-bold text-[#302521]">
                          {lang === 'ar' ? st.nameAr : st.name}
                        </p>
                        {lowAttendance ? (
                          <StatusBadge status="Attendance Watch" label={t('Below 85%', 'أقل من ٨٥٪')} />
                        ) : null}
                      </div>
                      <p className="mt-0.5 text-xs text-[#6E645D] tabular-nums">
                        GPA {st.gpa} · {t('Attendance', 'الحضور')}: {st.attendance}%
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => navigate('messages', { chatThread: `direct-${st.id}` })}
                      className="inline-flex min-h-[36px] items-center gap-1.5 rounded-lg border border-[#E8E3D9] bg-white px-3 py-1.5 text-xs font-semibold text-[#302521] hover:border-[#B81104] hover:text-[#B81104]"
                    >
                      <MessageSquare className="h-3.5 w-3.5" aria-hidden="true" />
                      <span>{t('Message', 'مراسلة')}</span>
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Advisee Petitions Queue */}
        <div className="cohort-card p-6 space-y-4">
          <h2 className="text-base font-bold text-[#302521]">
            {t('Student Petitions Requiring Academic Staff Decision', 'الالتماسات الطلابية بانتظار قرار هيئة التدريس')}
          </h2>
          <div className="divide-y divide-[#E8E3D9]">
            {data.petitions.map((pet) => (
              <div
                key={pet.id}
                className="flex flex-col justify-between gap-3 py-4 first:pt-1 last:pb-1 sm:flex-row sm:items-center"
              >
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm font-bold text-[#302521]">{pet.student}</span>
                    <span className="text-xs text-[#6E645D]">({pet.studentId})</span>
                    <StatusBadge status={pet.status} />
                  </div>
                  <p className="mt-1 text-xs font-semibold text-[#B81104]">
                    {lang === 'ar' ? pet.typeAr : pet.type} · {pet.date}
                  </p>
                  <p className="mt-1 text-xs text-[#6E645D]">{pet.detail}</p>
                </div>

                <div className="flex flex-wrap items-center gap-2 shrink-0">
                  <button
                    type="button"
                    onClick={() => updatePetitionStatus(pet.id, 'Approved')}
                    className="min-h-[38px] rounded-lg bg-[#16845B] px-3 py-1.5 text-xs font-bold text-white hover:opacity-90"
                  >
                    {t('Approve', 'اعتماد')}
                  </button>
                  <button
                    type="button"
                    onClick={() => updatePetitionStatus(pet.id, 'Rejected')}
                    className="min-h-[38px] rounded-lg border border-[#C93636]/40 bg-white px-3 py-1.5 text-xs font-bold text-[#C93636] hover:bg-[#FFE9E5]"
                  >
                    {t('Decline', 'رفض')}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>
    );
  }

  // STUDENT VIEW — Personal Academic Affairs & Analytics (#11)
  const completedCredits = 78;
  const totalCredits = 132;
  const creditPercent = Math.round((completedCredits / totalCredits) * 100);

  return (
    <section className="page-enter space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {t('ACADEMIC AFFAIRS · STUDENT ANALYTICS', 'الشؤون الأكاديمية · تحليلات الطالب')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {t('Academic Affairs & Progress Analytics', 'الشؤون الأكاديمية وتحليلات الأداء')}
          </h1>
          <p className="mt-1 text-sm text-[#6E645D]">
            {t(
              'Track your GPA progression, attendance thresholds, credit completion, what-if projections, and official petitions.',
              'تابع تطور معدلك التراكمي ونسب الحضور والساعات المكتملة والتوقعات والالتماسات الأكاديمية.'
            )}
          </p>
        </div>

        <button
          type="button"
          onClick={() => navigate('registration')}
          className="min-h-[42px] rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
        >
          {t('Go to Course Registration (Up to 7)', 'الانتقال لتسجيل المقررات (حتى ٧)')}
        </button>
      </div>

      <ProfileHubNav />

      {/* Student 4 KPI Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <div className="cohort-card p-5">
          <div className="flex items-center justify-between text-xs font-semibold text-[#6E645D]">
            <span>{t('Cumulative GPA', 'المعدل التراكمي')}</span>
            <TrendingUp className="h-4 w-4 text-[#16845B]" aria-hidden="true" />
          </div>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">
            3.82 <span className="text-sm font-medium text-[#6E645D]">/ 4.00</span>
          </p>
          <p className="mt-1 text-xs font-semibold text-[#16845B]">
            {t('+0.08 vs Spring 2026', '+0.08 عن ربيع ٢٠٢٦')}
          </p>
        </div>

        <div className="cohort-card p-5">
          <div className="flex items-center justify-between text-xs font-semibold text-[#6E645D]">
            <span>{t('Current Term Average', 'معدل الفصل الحالي')}</span>
            <Award className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
          </div>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">88.7%</p>
          <p className="mt-1 text-xs text-[#6E645D]">
            {t('Dean’s List Honoree', 'مُدرج بقائمة العميد للشرف')}
          </p>
        </div>

        <div className="cohort-card p-5">
          <div className="flex items-center justify-between text-xs font-semibold text-[#6E645D]">
            <span>{t('Credits Earned', 'الساعات المعتمدة المكتملة')}</span>
            <BookOpen className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
          </div>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">
            {completedCredits} <span className="text-sm font-medium text-[#6E645D]">/ {totalCredits}</span>
          </p>
          <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-[#EFECE5]">
            <div className="h-full rounded-full bg-[#B81104]" style={{ width: `${creditPercent}%` }} />
          </div>
        </div>

        <div className="cohort-card p-5">
          <div className="flex items-center justify-between text-xs font-semibold text-[#6E645D]">
            <span>{t('Overall Attendance', 'نسبة الحضور الإجمالية')}</span>
            <CheckCircle2 className="h-4 w-4 text-[#16845B]" aria-hidden="true" />
          </div>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">94.2%</p>
          <p className="mt-1 text-xs font-semibold text-[#16845B]">
            {t('Above 85% minimum threshold', 'أعلى من الحد الأدنى المطلوب ٨٥٪')}
          </p>
        </div>
      </div>

      {/* Semester GPA Chart + Course Standing Table */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        <div className="cohort-card p-6 lg:col-span-5 flex flex-col justify-between">
          <div>
            <h2 className="text-base font-bold text-[#302521]">
              {t('Semester GPA Progression', 'تطور المعدل الفصلي')}
            </h2>
            <p className="text-xs text-[#6E645D]">
              {t('Four-term trajectory across completed credit hours', 'المسار عبر آخر ٤ فصول دراسية')}
            </p>
          </div>

          <div className="mt-6 flex items-end justify-between gap-3 h-44 pt-4">
            {STUDENT_GPA_HISTORY.map((item, idx) => {
              const heightPct = Math.round((item.gpa / 4.0) * 100);
              const isLatest = idx === STUDENT_GPA_HISTORY.length - 1;
              return (
                <div key={item.term} className="flex flex-1 flex-col items-center gap-2 h-full justify-end">
                  <span className="text-xs font-extrabold text-[#302521] tabular-nums">
                    {item.gpa.toFixed(2)}
                  </span>
                  <div className="w-full max-w-[54px] flex-1 flex items-end rounded-lg bg-[#FCFBF6] p-1 border border-[#E8E3D9]">
                    <div
                      className={`w-full rounded-md transition-all ${
                        isLatest ? 'bg-[#B81104]' : 'bg-[#E9DBA9]'
                      }`}
                      style={{ height: `${heightPct}%` }}
                    />
                  </div>
                  <span className="text-center text-[10px] font-semibold text-[#6E645D] leading-tight">
                    {lang === 'ar' ? item.termAr : item.term}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        <div className="cohort-card p-6 lg:col-span-7 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-base font-bold text-[#302521]">
                {t('Course Grades & Attendance vs. 85% Rule', 'درجات المقررات ونسبة الحضور مقارنة بالحد الأدنى ٨٥٪')}
              </h2>
              <p className="text-xs text-[#6E645D]">
                {t('Click any course to open its full workspace', 'اضغط على أي مقرر لفتح مساحته الكاملة')}
              </p>
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-start text-xs">
              <thead>
                <tr className="border-b border-[#E8E3D9] text-[#6E645D]">
                  <th className="py-2.5 pe-3 font-semibold text-start">{t('Course', 'المقرر')}</th>
                  <th className="px-2 py-2.5 font-semibold text-center">{t('Credits', 'الساعات')}</th>
                  <th className="px-2 py-2.5 font-semibold text-center">{t('Grade', 'الدرجة')}</th>
                  <th className="px-2 py-2.5 font-semibold text-center">{t('Attendance', 'الحضور')}</th>
                  <th className="ps-2 py-2.5 font-semibold text-end">{t('Standing', 'الوضع')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#E8E3D9]">
                {data.courses.map((c) => {
                  const attOk = c.attendance >= 90;
                  return (
                    <tr key={c.id} className="hover:bg-[#FCFBF6]">
                      <td className="py-3 pe-3">
                        <button
                          type="button"
                          onClick={() => navigate('courses', { courseId: c.id, courseTab: 'Grades' })}
                          className="text-start font-bold text-[#302521] hover:text-[#B81104]"
                        >
                          {c.id} · {lang === 'ar' ? c.nameAr : c.name}
                        </button>
                      </td>
                      <td className="px-2 py-3 text-center tabular-nums">{c.credits}</td>
                      <td className="px-2 py-3 text-center font-bold text-[#302521] tabular-nums">{c.grade}%</td>
                      <td className="px-2 py-3 text-center tabular-nums">
                        <span className={c.attendance < 88 ? 'font-bold text-[#B76E00]' : 'font-semibold text-[#16845B]'}>
                          {c.attendance}%
                        </span>
                      </td>
                      <td className="ps-2 py-3 text-end">
                        <StatusBadge
                          status={attOk ? 'Approved' : 'Developing'}
                          label={attOk ? t('On Track', 'منتظم') : t('Monitor', 'متابعة')}
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* What-If Calculator + Advisor & Petitions */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        <div className="cohort-card p-6 lg:col-span-5 space-y-4">
          <div className="flex items-center gap-2">
            <Calculator className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
            <h2 className="text-base font-bold text-[#302521]">
              {t('What-If Grade & GPA Simulator', 'محاكاة الدرجات والمعدل التراكمي')}
            </h2>
          </div>
          <p className="text-xs text-[#6E645D]">
            {t('Weights: 60% Coursework + 40% Final Exam. Scenario preview only.', 'الأوزان: ٦٠٪ أعمال السنة + ٤٠٪ الامتحان النهائي (معاينة تقديرية).')}
          </p>

          <div className="space-y-3">
            <div>
              <label htmlFor="calc-coursework" className="flex justify-between text-xs font-semibold text-[#302521] mb-1">
                <span>{t('Current Coursework (%)', 'درجة أعمال السنة (٪)')}</span>
                <span className="tabular-nums text-[#B81104]">{courseworkScore}%</span>
              </label>
              <input
                id="calc-coursework"
                type="range"
                min="0"
                max="100"
                value={courseworkScore}
                onChange={(e) => setCourseworkScore(Number(e.target.value))}
                className="w-full accent-[#B81104]"
              />
            </div>

            <div>
              <label htmlFor="calc-final" className="flex justify-between text-xs font-semibold text-[#302521] mb-1">
                <span>{t('Expected Final Exam (%)', 'الدرجة المتوقعة للنهائي (٪)')}</span>
                <span className="tabular-nums text-[#B81104]">{expectedFinal}%</span>
              </label>
              <input
                id="calc-final"
                type="range"
                min="0"
                max="100"
                value={expectedFinal}
                onChange={(e) => setExpectedFinal(Number(e.target.value))}
                className="w-full accent-[#B81104]"
              />
            </div>
          </div>

          <div className="cohort-lemon-panel rounded-xl p-4 flex items-center justify-between">
            <div>
              <p className="text-xs font-semibold text-[#6E645D]">{t('Projected Result', 'النتيجة المتوقعة')}</p>
              <p className="text-2xl font-extrabold text-[#B81104] tabular-nums">{projectedScore}%</p>
            </div>
            <div className="text-end">
              <p className="text-xs font-semibold text-[#6E645D]">{t('Est. Term GPA', 'المعدل المتوقع')}</p>
              <p className="text-2xl font-extrabold text-[#302521] tabular-nums">{projectedGpa}</p>
            </div>
          </div>
        </div>

        {/* Academic Advisor & Petitions */}
        <div className="cohort-card p-6 lg:col-span-7 space-y-5">
          <div className="flex flex-col justify-between gap-3 rounded-xl border border-[#E9DBA9] bg-[#FFF9E4] p-4 sm:flex-row sm:items-center">
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-[#B81104]">
                {t('YOUR ACADEMIC ADVISOR', 'المرشد الأكاديمي الخاص بك')}
              </span>
              <h3 className="mt-0.5 text-base font-bold text-[#302521]">
                {lang === 'ar' ? advisor?.nameAr : advisor?.name}
              </h3>
              <p className="text-xs text-[#6E645D]">
                {advisor?.room} · {advisor?.officeHours}
              </p>
            </div>
            <button
              type="button"
              onClick={() => navigate('messages', { chatThread: 'advisor-leila' })}
              className="inline-flex min-h-[40px] items-center gap-2 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
            >
              <MessageSquare className="h-4 w-4" aria-hidden="true" />
              <span>{t('Ask Academic Advisor', 'مراسلة المرشد الأكاديمي')}</span>
            </button>
          </div>

          <form onSubmit={handlePetitionSubmit} className="space-y-3">
            <div className="flex items-center gap-2">
              <FileText className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
              <h2 className="text-sm font-bold text-[#302521]">
                {t('Submit Official Academic Petition', 'تقديم التماس أكاديمي رسمي')}
              </h2>
            </div>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="sm:col-span-1">
                <label htmlFor="petition-type" className="sr-only">
                  {t('Petition Type', 'نوع الطلب')}
                </label>
                <select
                  id="petition-type"
                  value={petitionType}
                  onChange={(e) => setPetitionType(e.target.value)}
                  className="w-full min-h-[42px] rounded-xl border border-[#D6CFC1] bg-white px-3 text-xs font-semibold text-[#302521]"
                >
                  <option value="Course Overload / Schedule Adjustment">
                    {t('Course / Schedule Petition', 'تعديل جدول / تسجيل')}
                  </option>
                  <option value="Grade Review Request">
                    {t('Grade Review Request', 'طلب مراجعة درجة')}
                  </option>
                  <option value="Attendance Excuse (Medical)">
                    {t('Attendance Excuse', 'عذر غياب')}
                  </option>
                  <option value="Profile Record Correction">
                    {t('Profile Record Correction', 'تصحيح بيانات السجل')}
                  </option>
                </select>
              </div>
              <div className="sm:col-span-2 flex gap-2">
                <input
                  type="text"
                  required
                  value={petitionDetail}
                  onChange={(e) => setPetitionDetail(e.target.value)}
                  placeholder={t('Describe your request for Academic Affairs…', 'اكتب تفاصيل الالتماس للشؤون الأكاديمية…')}
                  className="min-h-[42px] flex-1 rounded-xl border border-[#D6CFC1] bg-white px-3 text-xs text-[#302521] focus:border-[#B81104] focus:outline-none"
                />
                <button
                  type="submit"
                  className="inline-flex min-h-[42px] items-center gap-1.5 rounded-xl bg-[#B81104] px-4 text-xs font-bold text-white hover:bg-[#940E03]"
                >
                  <Send className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('Submit', 'إرسال')}</span>
                </button>
              </div>
            </div>
          </form>

          <div className="divide-y divide-[#E8E3D9] border-t border-[#E8E3D9] pt-2">
            {data.petitions.map((pet) => (
              <div key={pet.id} className="flex items-center justify-between gap-3 py-2.5 text-xs">
                <div>
                  <p className="font-bold text-[#302521]">{lang === 'ar' ? pet.typeAr : pet.type}</p>
                  <p className="text-[#6E645D]">{pet.detail}</p>
                </div>
                <StatusBadge status={pet.status} />
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
