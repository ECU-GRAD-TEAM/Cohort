import React, { useMemo, useState } from 'react';
import {
  CheckCircle2,
  ClipboardCheck,
  ListChecks,
  Send,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { StatusBadge } from '../common/StatusBadge';
import { WaygroundBuilder, WaygroundPlayer } from '../common/WaygroundTemplateStudio';

export function GradingPage() {
  const { role, lang, t, data, setData, showToast, navigate } = useCohort();
  const isStaff = role === 'Academic Staff';

  const [activeTab, setActiveTab] = useState('gradebook');
  const [statusFilter, setStatusFilter] = useState('All');

  // Interactive Player Selection (Assignments + Quizzes)
  const playableItems = useMemo(() => {
    const asgList = (data.assignments || [])
      .filter((a) => (a.questions || []).length > 0)
      .map((a) => ({ kind: 'assignment', item: a }));
    const qzList = (data.quizzes || [])
      .filter((q) => (q.questions || []).length > 0)
      .map((q) => ({ kind: 'quiz', item: q }));
    return [...asgList, ...qzList];
  }, [data.assignments, data.quizzes]);

  const [selectedPlayableKey, setSelectedPlayableKey] = useState(() => {
    const firstAsg = data.assignments?.find((a) => (a.questions || []).length > 0);
    if (firstAsg) return `assignment:${firstAsg.id}`;
    const firstQz = data.quizzes?.find((q) => (q.questions || []).length > 0);
    return firstQz ? `quiz:${firstQz.id}` : '';
  });

  const activePlayable = useMemo(() => {
    const found = playableItems.find(
      (entry) => `${entry.kind}:${entry.item.id}` === selectedPlayableKey
    );
    return found || playableItems[0] || null;
  }, [playableItems, selectedPlayableKey]);

  // Student Grade Appeal State
  const [appealAssessment, setAppealAssessment] = useState('');
  const [appealCourse, setAppealCourse] = useState(data.courses[0]?.id || 'CS201');
  const [appealReason, setAppealReason] = useState('');

  const visibleReviews = useMemo(() => {
    const base = isStaff
      ? data.gradeReviews
      : data.gradeReviews.filter((g) => g.student === 'Alex Chen');
    if (statusFilter === 'All') return base;
    return base.filter((g) => g.status === statusFilter);
  }, [data.gradeReviews, isStaff, statusFilter]);

  const counts = useMemo(() => {
    const base = isStaff
      ? data.gradeReviews
      : data.gradeReviews.filter((g) => g.student === 'Alex Chen');
    return {
      total: base.length,
      needsReview: base.filter((g) => g.status === 'Needs review').length,
      approved: base.filter((g) => g.status === 'Approved').length,
      published: base.filter((g) => g.status === 'Published').length,
    };
  }, [data.gradeReviews, isStaff]);

  const updateGradeField = (id, patch) => {
    setData((prev) => ({
      ...prev,
      gradeReviews: prev.gradeReviews.map((item) =>
        item.id === id ? { ...item, ...patch } : item
      ),
    }));
  };

  const handlePublishApproved = () => {
    const approvedCount = data.gradeReviews.filter((g) => g.status === 'Approved').length;
    if (!approvedCount) {
      showToast(t('No approved rows waiting to publish', 'لا توجد درجات معتمدة جاهزة للنشر'));
      return;
    }
    setData((prev) => ({
      ...prev,
      gradeReviews: prev.gradeReviews.map((item) =>
        item.status === 'Approved' ? { ...item, status: 'Published' } : item
      ),
    }));
    showToast(
      t(
        `Published ${approvedCount} approved grade(s) to student transcripts`,
        `تم نشر ${approvedCount} درجة معتمدة للطلاب`
      )
    );
  };

  const handleStudentAppeal = (e) => {
    e.preventDefault();
    if (!appealAssessment.trim() || !appealReason.trim()) {
      showToast(t('Enter assessment name and reason', 'أدخل اسم التقييم وسبب المراجعة'));
      return;
    }
    const newItem = {
      id: `gr-${Date.now()}`,
      student: 'Alex Chen',
      course: appealCourse,
      assessment: appealAssessment.trim(),
      score: 85,
      status: 'Needs review',
      feedback: `Appeal: ${appealReason.trim()}`,
    };
    setData((prev) => ({
      ...prev,
      gradeReviews: [newItem, ...prev.gradeReviews],
    }));
    setAppealAssessment('');
    setAppealReason('');
    showToast(t('Grade review appeal submitted', 'تم إرسال طلب مراجعة الدرجة'));
  };

  return (
    <section className="page-enter space-y-6">
      <div className="cohort-card bg-white rounded-3xl p-6 sm:p-7 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-5">
        <div>
          <p className="text-[11px] font-bold tracking-widest uppercase text-[#B81104]">
            {isStaff
              ? t('ACADEMIC STAFF · GRADING & ASSESSMENT STUDIO', 'هيئة التدريس · التقييم وبناء القوالب')
              : t('ASSESSMENT RESULTS & TEMPLATES', 'نتائج التقييمات ونماذج الأسئلة')}
          </p>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-[#1A1715] mt-1">
            {isStaff
              ? t('Gradebook Review & Assignment / Quiz Studio', 'سجل الدرجات واستوديو التكليفات والاختبارات')
              : t('Grades, Appeals & Interactive Templates', 'الدرجات والالتماسات ونماذج الأسئلة التفاعلية')}
          </h1>
          <p className="text-sm text-[#6E645D] mt-1.5 max-w-2xl">
            {isStaff
              ? t(
                  'Approve student grade submissions, handle written appeals, and design interactive Assignments and Quizzes with MCQ, True/False, Fill-in-the-blanks, Open ended, and Matching questions.',
                  'اعتماد الدرجات ومراجعة الإجابات المقالية وتصميم قوالب التكليفات والاختبارات التفاعلية بجميع أنماط الأسئلة.'
                )
              : t(
                  'Inspect graded work, submit manual review appeals, and complete interactive Assignments and Quizzes across all question formats.',
                  'استعراض الدرجات وتقديم طلبات مراجعة وتنفيذ التكليفات والاختبارات التفاعلية بجميع الأنماط.'
                )}
          </p>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 shrink-0">
          <div className="rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] px-3.5 py-2.5 text-center">
            <div className="text-[11px] font-bold text-[#6E645D]">{t('Total', 'الإجمالي')}</div>
            <div className="text-xl font-extrabold text-[#1A1715] tabular-nums">{counts.total}</div>
          </div>
          <div className="rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] px-3.5 py-2.5 text-center">
            <div className="text-[11px] font-bold text-[#B81104]">{t('Needs Review', 'مراجعة')}</div>
            <div className="text-xl font-extrabold text-[#B81104] tabular-nums">
              {counts.needsReview}
            </div>
          </div>
          <div className="rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] px-3.5 py-2.5 text-center">
            <div className="text-[11px] font-bold text-[#6E645D]">{t('Approved', 'معتمد')}</div>
            <div className="text-xl font-extrabold text-[#1A1715] tabular-nums">
              {counts.approved}
            </div>
          </div>
          <div className="rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] px-3.5 py-2.5 text-center">
            <div className="text-[11px] font-bold text-[#146C43]">{t('Published', 'منشور')}</div>
            <div className="text-xl font-extrabold text-[#146C43] tabular-nums">
              {counts.published}
            </div>
          </div>
        </div>
      </div>

      {/* Mode Tabs */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div
          role="tablist"
          aria-label={t('Grading Workspace Views', 'أقسام التقييم')}
          className="inline-flex rounded-2xl bg-[#F4EFE6] p-1 border border-[#E5DCCF]"
        >
          <button
            type="button"
            role="tab"
            aria-selected={activeTab === 'gradebook'}
            onClick={() => setActiveTab('gradebook')}
            className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-bold transition-colors ${
              activeTab === 'gradebook'
                ? 'bg-[#B81104] text-[#FFFACD] shadow-sm'
                : 'text-[#6E645D] hover:text-[#1A1715]'
            }`}
          >
            <ClipboardCheck className="w-4 h-4" aria-hidden="true" />
            {isStaff
              ? t('Gradebook & Appeals', 'الدرجات والالتماسات')
              : t('My Grades & Appeals', 'درجاتي والالتماسات')}
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={activeTab === 'templates'}
            onClick={() => setActiveTab('templates')}
            className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-bold transition-colors ${
              activeTab === 'templates'
                ? 'bg-[#B81104] text-[#FFFACD] shadow-sm'
                : 'text-[#6E645D] hover:text-[#1A1715]'
            }`}
          >
            <ListChecks className="w-4 h-4" aria-hidden="true" />
            {t('Assignment & Quiz Studio', 'استوديو التكليفات والاختبارات')}
          </button>
        </div>

        {isStaff && activeTab === 'gradebook' && (
          <button
            type="button"
            onClick={handlePublishApproved}
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-[#B81104] text-[#FFFACD] text-sm font-bold hover:bg-[#960D03] transition-colors shadow-sm"
          >
            <CheckCircle2 className="w-4 h-4" aria-hidden="true" />
            {t('Publish All Approved', 'نشر جميع الدرجات المعتمدة')}
          </button>
        )}
      </div>

      {activeTab === 'gradebook' ? (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            {['All', 'Needs review', 'Draft', 'Approved', 'Published'].map((st) => (
              <button
                key={st}
                type="button"
                onClick={() => setStatusFilter(st)}
                className={`px-3.5 py-1.5 rounded-full text-xs font-bold border transition-colors ${
                  statusFilter === st
                    ? 'bg-[#FFFACD] text-[#960D03] border-[#B81104]'
                    : 'bg-white text-[#6E645D] border-[#E5DCCF] hover:border-[#B81104]/40'
                }`}
              >
                {st}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-1 gap-3">
            {visibleReviews.map((row) => (
              <div
                key={row.id}
                className="cohort-card rounded-2xl p-4 sm:p-5 flex flex-col lg:flex-row lg:items-center justify-between gap-4"
              >
                <div className="space-y-1 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="px-2.5 py-0.5 rounded-lg bg-[#FFFACD] text-[#960D03] text-xs font-extrabold border border-[#B81104]/25">
                      {row.course}
                    </span>
                    <span className="text-sm font-extrabold text-[#1A1715]">{row.student}</span>
                    <StatusBadge status={row.status} />
                  </div>
                  <p className="text-sm font-semibold text-[#1A1715]">{row.assessment}</p>
                  {isStaff ? (
                    <input
                      type="text"
                      aria-label={t(`Feedback for ${row.student}`, `ملاحظات ${row.student}`)}
                      value={row.feedback}
                      onChange={(e) => updateGradeField(row.id, { feedback: e.target.value })}
                      className="mt-1.5 w-full rounded-xl border border-[#E5DCCF] bg-[#FDFBF7] px-3 py-1.5 text-xs text-[#1A1715]"
                    />
                  ) : (
                    <p className="text-xs text-[#6E645D]">{row.feedback}</p>
                  )}
                </div>

                <div className="flex flex-wrap items-center gap-3 shrink-0">
                  <div className="flex items-center gap-1.5">
                    <span className="text-xs font-semibold text-[#6E645D]">
                      {t('Score', 'الدرجة')}
                    </span>
                    {isStaff ? (
                      <input
                        type="number"
                        min="0"
                        max="100"
                        aria-label={t(`Score for ${row.student}`, `درجة ${row.student}`)}
                        value={row.score}
                        onChange={(e) =>
                          updateGradeField(row.id, {
                            score: Math.min(100, Math.max(0, Number(e.target.value) || 0)),
                          })
                        }
                        className="w-20 rounded-xl border border-[#E5DCCF] bg-white px-2.5 py-1.5 text-sm font-extrabold text-[#1A1715] tabular-nums text-center"
                      />
                    ) : (
                      <span className="px-3 py-1.5 rounded-xl bg-[#FDFBF7] border border-[#E5DCCF] text-sm font-extrabold text-[#1A1715] tabular-nums">
                        {row.score}/100
                      </span>
                    )}
                  </div>

                  {isStaff && (
                    <select
                      aria-label={t(`Status for ${row.student}`, `حالة ${row.student}`)}
                      value={row.status}
                      onChange={(e) => {
                        updateGradeField(row.id, { status: e.target.value });
                        showToast(
                          t(`Updated ${row.student} → ${e.target.value}`, `تم تحديث الحالة إلى ${e.target.value}`)
                        );
                      }}
                      className="rounded-xl border border-[#E5DCCF] bg-white px-3 py-1.5 text-xs font-bold text-[#1A1715]"
                    >
                      <option value="Draft">Draft</option>
                      <option value="Needs review">Needs review</option>
                      <option value="Approved">Approved</option>
                      <option value="Published">Published</option>
                    </select>
                  )}
                </div>
              </div>
            ))}
          </div>

          {!isStaff && (
            <form
              onSubmit={handleStudentAppeal}
              className="cohort-card rounded-2xl p-5 space-y-3 border-dashed border-[#B81104]/30"
            >
              <h2 className="text-sm font-extrabold text-[#1A1715]">
                {t('Request Manual Grade Review', 'تقديم التماس مراجعة درجة')}
              </h2>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <select
                  aria-label={t('Course', 'المقرر')}
                  value={appealCourse}
                  onChange={(e) => setAppealCourse(e.target.value)}
                  className="rounded-xl border border-[#E5DCCF] bg-white px-3 py-2 text-sm"
                >
                  {data.courses.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.id} · {lang === 'ar' ? c.nameAr : c.name}
                    </option>
                  ))}
                </select>
                <input
                  type="text"
                  value={appealAssessment}
                  onChange={(e) => setAppealAssessment(e.target.value)}
                  placeholder={t('Assessment title (e.g., Quiz 1)', 'اسم التقييم')}
                  className="rounded-xl border border-[#E5DCCF] bg-white px-3 py-2 text-sm"
                />
                <input
                  type="text"
                  value={appealReason}
                  onChange={(e) => setAppealReason(e.target.value)}
                  placeholder={t('Reason for manual check...', 'سبب طلب المراجعة...')}
                  className="rounded-xl border border-[#E5DCCF] bg-white px-3 py-2 text-sm"
                />
              </div>
              <button
                type="submit"
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-[#B81104] text-[#FFFACD] text-xs font-bold hover:bg-[#960D03]"
              >
                <Send className="w-3.5 h-3.5" aria-hidden="true" />
                {t('Submit Appeal', 'إرسال الالتماس')}
              </button>
            </form>
          )}
        </div>
      ) : (
        /* Unified Interactive Assignment & Quiz Studio + Runner */
        <div className="space-y-6">
          {isStaff ? (
            <WaygroundBuilder
              defaultTargetType="assignment"
              allowTargetSwitch
              onSaved={({ id, targetType }) => {
                if (id && id !== 'new') {
                  setSelectedPlayableKey(`${targetType}:${id}`);
                }
              }}
            />
          ) : null}

          <div className="cohort-card rounded-2xl p-5 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <span className="text-[11px] font-bold uppercase tracking-wider text-[#B81104]">
                  {isStaff
                    ? t('TA & Faculty Student-View Simulator', 'محاكي تجربة الطالب للمعيد والمحاضر')
                    : t('Complete Interactive Assignments & Quizzes', 'حل التكليفات والاختبارات التفاعلية')}
                </span>
                <h2 className="text-lg font-extrabold text-[#1A1715]">
                  {t('Select an Interactive Assignment or Quiz', 'اختر تكليفًا أو اختبارًا للتنفيذ أو المعاينة')}
                </h2>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <select
                  aria-label={t('Select interactive assignment or quiz', 'اختر التكليف أو الاختبار')}
                  value={activePlayable ? `${activePlayable.kind}:${activePlayable.item.id}` : ''}
                  onChange={(e) => setSelectedPlayableKey(e.target.value)}
                  className="rounded-xl border border-[#E5DCCF] bg-[#FDFBF7] px-3 py-2 text-xs font-bold text-[#1A1715]"
                >
                  {playableItems.map(({ kind, item }) => (
                    <option key={`${kind}:${item.id}`} value={`${kind}:${item.id}`}>
                      [{kind === 'assignment' ? t('Assignment', 'تكليف') : t('Quiz', 'اختبار')}] {item.course} ·{' '}
                      {lang === 'ar' ? item.titleAr : item.title} ({(item.questions || []).length} Qs)
                    </option>
                  ))}
                </select>

                {activePlayable ? (
                  <button
                    type="button"
                    onClick={() =>
                      navigate('courses', {
                        courseId: activePlayable.item.course,
                        courseTab:
                          activePlayable.kind === 'assignment' ? 'Assignments' : 'Quizzes & Exams',
                      })
                    }
                    className="rounded-xl border border-[#E5DCCF] bg-white px-3.5 py-2 text-xs font-bold text-[#1A1715] hover:border-[#B81104]"
                  >
                    {t('Open in Course', 'فتح في المقرر')} →
                  </button>
                ) : null}
              </div>
            </div>

            {activePlayable ? (
              <WaygroundPlayer
                item={activePlayable.item}
                itemType={activePlayable.kind}
                isStaff={isStaff}
              />
            ) : null}
          </div>
        </div>
      )}
    </section>
  );
}
