import React, { useMemo, useState } from 'react';
import {
  BookOpen,
  ClipboardList,
  ExternalLink,
  Filter,
  HelpCircle,
  MapPin,
  Send,
  Sparkles,
  Trash2,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { CAMPUS_LOCATIONS, DIRECTORY_PEOPLE } from '../../data/seedData';

const FILTER_MODES = [
  { id: 'General', labelEn: 'General University', labelAr: 'عام (الجامعة)' },
  { id: 'Course', labelEn: 'By Specific Course', labelAr: 'حسب مقرر محدد' },
  { id: 'Materials', labelEn: 'Course Materials', labelAr: 'المواد الدراسية' },
  { id: 'Assignments', labelEn: 'Assignments & Rubrics', labelAr: 'التكليفات ومعايير التقييم' },
  { id: 'Exams', labelEn: 'Quizzes & Exams', labelAr: 'الاختبارات والامتحانات' },
  { id: 'Directory', labelEn: 'People & Campus Map', labelAr: 'الدليل والخريطة' },
];

const COURSE_SCOPED_MODES = ['Course', 'Materials', 'Assignments', 'Exams'];

export function AssistantPage() {
  const { role, lang, t, data, setData, navigate, showToast } = useCohort();
  const [filterMode, setFilterMode] = useState('General');
  const [selectedCourse, setSelectedCourse] = useState(data.courses[0]?.id || 'CS201');
  const [selectedItemId, setSelectedItemId] = useState('ALL');
  const [input, setInput] = useState('');

  const isStaff = role === 'Academic Staff';
  const courseObj = useMemo(
    () => data.courses.find((c) => c.id === selectedCourse) || data.courses[0],
    [data.courses, selectedCourse]
  );

  const courseMaterials = useMemo(
    () => data.materials.filter((m) => m.course === selectedCourse),
    [data.materials, selectedCourse]
  );
  const courseAssignments = useMemo(
    () => data.assignments.filter((a) => a.course === selectedCourse),
    [data.assignments, selectedCourse]
  );
  const courseQuizzes = useMemo(
    () => data.quizzes.filter((q) => q.course === selectedCourse),
    [data.quizzes, selectedCourse]
  );

  const specificItems = useMemo(() => {
    if (filterMode === 'Materials') return courseMaterials;
    if (filterMode === 'Assignments') return courseAssignments;
    if (filterMode === 'Exams') return courseQuizzes;
    return [];
  }, [courseAssignments, courseMaterials, courseQuizzes, filterMode]);

  const focusedSpecificItem = useMemo(
    () => specificItems.find((item) => item.id === selectedItemId) || null,
    [selectedItemId, specificItems]
  );

  const quickPrompts = useMemo(() => {
    if (filterMode === 'Directory') {
      return isStaff
        ? [
            t('Where is Eng. Kareem Adel room & office hours?', 'أين غرفة م. كريم عادل وساعاته المكتبية؟'),
            t('Locate Dr. Elena Vance (Registrar) on Campus Map', 'أين مكتب د. إيلينا فانس (المسجل)؟'),
            t('Which advisees currently need attendance monitoring?', 'أي طلاب إرشاد يحتاجون متابعة الحضور؟'),
          ]
        : [
            t('Who is my Academic Advisor and where is their office?', 'من مرشدي الأكاديمي وأين يقع مكتبه؟'),
            t('Where is Lab C-102 and Eng. Kareem TA office hours?', 'أين معمل C-102 وساعات م. كريم المكتبية؟'),
            t('Where is the Student Affairs office located?', 'أين يقع مكتب شؤون الطلاب؟'),
          ];
    }

    if (filterMode === 'Assignments') {
      return isStaff
        ? [
            t(`Summarize interactive questions & rubric for ${selectedCourse}`, `لخّص الأسئلة التفاعلية ومعايير التقييم لمقرر ${selectedCourse}`),
            t('Check which course assignments are graded vs upcoming', 'استعرض التكليفات المصححة والقادمة'),
          ]
        : [
            t(`What interactive questions & deadline are in ${selectedCourse} assignments?`, `ما الأسئلة التفاعلية والموعد النهائي لتكليفات ${selectedCourse}؟`),
            t('How is the written question rubric evaluated?', 'كيف يتم تقييم السؤال المقالي في التكليف؟'),
          ];
    }

    if (filterMode === 'Exams') {
      return isStaff
        ? [
            t(`Review ${selectedCourse} quiz checkpoint status & question types`, `راجع حالة اختبار ${selectedCourse} وأنواع الأسئلة`),
            t('Which student grade appeals need review right now?', 'ما التماسات الدرجات التي تحتاج مراجعة الآن؟'),
          ]
        : [
            t('What deadlines, quizzes, and exams do I have next?', 'ما المواعيد النهائية والاختبارات والامتحانات القادمة؟'),
            t('Where is the CS305 Midterm Exam hall?', 'أين قاعة امتحان منتصف الفصل لـ CS305؟'),
          ];
    }

    if (filterMode === 'Materials') {
      return [
        t(`Summarize ${selectedCourse} lecture & lab study notes`, `لخّص ملاحظات محاضرات ومعامل ${selectedCourse}`),
        t('Show the latest uploaded material version', 'اعرض أحدث إصدار من المواد الدراسية'),
      ];
    }

    return isStaff
      ? [
          t('Which student grade appeals need review right now?', 'ما التماسات الدرجات التي تحتاج مراجعة الآن؟'),
          t('Summarize open advisee registration petitions', 'لخّص طلبات التسجيل المعلقة للطلاب'),
          t(`Draft a multi-format question outline for ${selectedCourse}`, `اقترح مخطط أسئلة متعددة الأنواع لمقرر ${selectedCourse}`),
          t('Check upcoming office hours bookings', 'راجع حجوزات الساعات المكتبية القادمة'),
        ]
      : [
          t('What deadlines and exams do I have next?', 'ما المواعيد النهائية والامتحانات القادمة؟'),
          t(`Summarize ${selectedCourse} topic focus and study notes`, `لخّص محور مقرر ${selectedCourse} وملاحظاته`),
          t('Who is my Academic Advisor and where is their office?', 'من مرشدي الأكاديمي وأين يقع مكتبه؟'),
          t('How many courses can I register this semester?', 'كم عدد المقررات المسموح بتسجيلها هذا الفصل؟'),
        ];
  }, [filterMode, isStaff, selectedCourse, t]);

  const handleModeChange = (nextMode) => {
    setFilterMode(nextMode);
    setSelectedItemId('ALL');
  };

  const handleCourseChange = (nextCourse) => {
    setSelectedCourse(nextCourse);
    setSelectedItemId('ALL');
  };

  const buildGroundedReply = (questionText) => {
    const q = questionText.toLowerCase();

    // 1. Directory & Campus Map grounded lookup
    if (
      filterMode === 'Directory' ||
      q.includes('advisor') ||
      q.includes('office') ||
      q.includes('where') ||
      q.includes('room') ||
      q.includes('kareem') ||
      q.includes('elena') ||
      q.includes('tarek') ||
      q.includes('lab') ||
      q.includes('مرشد') ||
      q.includes('غرفة') ||
      q.includes('معمل') ||
      q.includes('أين')
    ) {
      const matchedPerson = DIRECTORY_PEOPLE.find((p) => {
        const hay = `${p.name} ${p.nameAr} ${p.subRole} ${p.room}`.toLowerCase();
        return q
          .split(/\s+/)
          .filter((w) => w.length > 2)
          .some((token) => hay.includes(token));
      });
      const targetPerson =
        matchedPerson || DIRECTORY_PEOPLE.find((p) => p.isAdvisor) || DIRECTORY_PEOPLE[0];
      const bldg = CAMPUS_LOCATIONS.find((b) => b.id === targetPerson?.buildingId);

      if (q.includes('advisee') || q.includes('attendance watch') || q.includes('إرشاد')) {
        const watchList = DIRECTORY_PEOPLE.filter(
          (p) => p.category === 'Student' && (p.attendance || 100) < 85
        );
        return {
          text: t(
            `Advisee attendance summary: ${watchList.length} student(s) currently below the 85% threshold (${watchList
              .map((w) => `${w.name}: ${w.attendance}%`)
              .join(', ') || 'None'}).`,
            `ملخص حضور طلاب الإرشاد: ${watchList.length} طالب دون حد ٨٥٪ (${watchList
              .map((w) => `${w.nameAr}: ${w.attendance}%`)
              .join('، ')}).`
          ),
          source: t('Campus Directory · Advisee Standing', 'دليل الطلاب · حالة الحضور'),
          targetPage: 'academic-affairs',
          actionLabel: t('Open Academic Affairs', 'فتح الشؤون الأكاديمية'),
        };
      }

      return {
        text: t(
          `${targetPerson.name} (${targetPerson.subRole}) — ${targetPerson.room}${targetPerson.officeHours ? ` · Office Hours: ${targetPerson.officeHours}` : ''}.${bldg ? ` Building: ${bldg.name} (${bldg.zone}).` : ''}`,
          `${targetPerson.nameAr} (${targetPerson.subRoleAr}) — ${targetPerson.room}${targetPerson.officeHours ? ` · الساعات المكتبية: ${targetPerson.officeHours}` : ''}.${bldg ? ` المبنى: ${bldg.nameAr}.` : ''}`
        ),
        source: `${t('Campus Directory & Map', 'دليل الجامعة والخريطة')} · ${targetPerson.room}`,
        targetPage: 'map',
        buildingId: targetPerson.buildingId,
        actionLabel: t('Locate on Campus Map', 'عرض على خريطة الحرم'),
      };
    }

    // 2. Assignments & Rubrics grounded lookup
    if (
      filterMode === 'Assignments' ||
      q.includes('assignment') ||
      q.includes('rubric') ||
      q.includes('تكليف') ||
      q.includes('معايير')
    ) {
      const targetAsg =
        (focusedSpecificItem && filterMode === 'Assignments' ? focusedSpecificItem : null) ||
        courseAssignments[0] ||
        data.assignments[0];
      if (!targetAsg) {
        return {
          text: t(
            `No interactive assignments are currently listed under ${selectedCourse}.`,
            `لا توجد تكليفات مضافة حاليًا لمقرر ${selectedCourse}.`
          ),
          source: `${selectedCourse} Assignments`,
          targetPage: 'courses',
          courseId: selectedCourse,
          courseTab: 'Assignments',
          actionLabel: t('Open Assignments Tab', 'فتح تبويب التكليفات'),
        };
      }
      const qCount = (targetAsg.questions || []).length;
      const totalPts = (targetAsg.questions || []).reduce((acc, item) => acc + (item.points || 0), 0);
      const writtenQ = (targetAsg.questions || []).find((item) => item.rubric);
      return {
        text: t(
          `[${targetAsg.course} · ${targetAsg.title}] Due ${targetAsg.due}. Format: ${targetAsg.templateType || 'Interactive Template'} (${qCount} questions, ${totalPts} pts). ${targetAsg.instructions}${writtenQ ? ` Written rubric focus: "${writtenQ.rubric}".` : ''}`,
          `[${targetAsg.course} · ${targetAsg.titleAr || targetAsg.title}] الموعد: ${targetAsg.due}. يحتوي على ${qCount} أسئلة (${totalPts} درجة). ${writtenQ ? `معيار التصحيح المقالي: "${writtenQ.rubric}".` : ''}`
        ),
        source: `${targetAsg.course} · ${targetAsg.title}`,
        targetPage: 'courses',
        courseId: targetAsg.course,
        courseTab: 'Assignments',
        actionLabel: t('Open Assignment Studio', 'فتح استوديو التكليف'),
      };
    }

    // 3. Course Materials grounded lookup
    if (
      filterMode === 'Materials' ||
      q.includes('material') ||
      q.includes('notes') ||
      q.includes('slides') ||
      q.includes('مادة') ||
      q.includes('مواد') ||
      q.includes('ملخص')
    ) {
      const mat =
        (focusedSpecificItem && filterMode === 'Materials' ? focusedSpecificItem : null) ||
        courseMaterials[0] ||
        data.materials[0];
      return {
        text: t(
          `From ${mat.course} "${mat.title}" (${mat.folder} · v${mat.version}, updated ${mat.date}): ${mat.notes}`,
          `من مادة ${mat.course} "${mat.title}" (الإصدار ${mat.version}): ${mat.notes}`
        ),
        source: `${mat.course} · ${mat.title} (v${mat.version})`,
        targetPage: 'courses',
        courseId: mat.course,
        courseTab: 'Materials',
        actionLabel: t('Open Course Materials', 'فتح المواد الدراسية'),
      };
    }

    // 4. Quizzes & Exams grounded lookup
    if (
      filterMode === 'Exams' ||
      q.includes('deadline') ||
      q.includes('exam') ||
      q.includes('quiz') ||
      q.includes('due') ||
      q.includes('امتحان') ||
      q.includes('اختبار')
    ) {
      if (focusedSpecificItem && filterMode === 'Exams') {
        const qCount = (focusedSpecificItem.questions || []).length;
        return {
          text: t(
            `[${focusedSpecificItem.course} · ${focusedSpecificItem.title}] ${focusedSpecificItem.kind} (${focusedSpecificItem.status}) · Scheduled ${focusedSpecificItem.date} · Duration ${focusedSpecificItem.duration} min.${focusedSpecificItem.room ? ` Hall: ${focusedSpecificItem.room}.` : ''} Includes ${qCount} interactive question(s).`,
            `[${focusedSpecificItem.course} · ${focusedSpecificItem.titleAr || focusedSpecificItem.title}] الموعد: ${focusedSpecificItem.date} · المدة ${focusedSpecificItem.duration} دقيقة · ${qCount} أسئلة.`
          ),
          source: `${focusedSpecificItem.course} · ${focusedSpecificItem.title}`,
          targetPage: 'courses',
          courseId: focusedSpecificItem.course,
          courseTab: 'Quizzes & Exams',
          actionLabel: t('Open Quiz & Exam View', 'فتح الاختبار في المقرر'),
        };
      }

      const upcoming = data.assignments.filter((a) => !a.submitted);
      const nextExam = data.quizzes.find((qz) => qz.kind === 'Exam');
      const activeQuiz = courseQuizzes[0] || data.quizzes[0];
      return {
        text: t(
          `Upcoming assessments: ${upcoming.length} pending assignment(s) (${upcoming
            .map((a) => `${a.course}: ${a.title} due ${a.due}`)
            .join('; ')}). Active quiz in ${selectedCourse}: ${activeQuiz ? `${activeQuiz.title} (${activeQuiz.duration} min · ${(activeQuiz.questions || []).length} questions)` : 'None'}.${nextExam ? ` Next Midterm Exam: ${nextExam.course} on ${nextExam.date} at ${nextExam.room}.` : ''}`,
          `التقييمات القادمة: ${upcoming.length} تكليفات قيد التسليم، والاختبار المتاح: ${activeQuiz ? `${activeQuiz.course} (${activeQuiz.duration} دقيقة)` : 'لا يوجد'}.${nextExam ? ` الامتحان القادم: ${nextExam.course} بتاريخ ${nextExam.date} في ${nextExam.room}.` : ''}`
        ),
        source: t('Assignments, Quizzes & Exam Schedule Store', 'سجل التكليفات والاختبارات والامتحانات'),
        targetPage: 'schedule',
        actionLabel: t('Open Schedule & Calendar', 'فتح الجدول والتقويم'),
      };
    }

    // 5. Registration & 7-Course Policy
    if (q.includes('register') || q.includes('7') || q.includes('credit') || q.includes('تسجيل')) {
      return {
        text: t(
          `Course Registration allows up to 7 courses per term (Lecture, Lab, and Section components) with automatic prerequisite and schedule-clash checks. Currently ${data.registrations.length} approved registration(s) are recorded.`,
          `يتيح نظام التسجيل حتى ٧ مقررات في الفصل (محاضرة ومعمل وسكشن) مع فحص المتطلبات والتعارض تلقائيًا. لديك حاليًا ${data.registrations.length} مقررات مسجلة.`
        ),
        source: t('Cohort Registration Policy · Max 7 Courses', 'لائحة التسجيل · حد ٧ مقررات'),
        targetPage: 'registration',
        actionLabel: t('Open Course Registration', 'فتح تسجيل المقررات'),
      };
    }

    // 6. Appeals, Petitions & Staff Workflows
    if (
      q.includes('appeal') ||
      q.includes('grade') ||
      q.includes('petition') ||
      q.includes('draft') ||
      q.includes('التماس') ||
      q.includes('درجات')
    ) {
      if (q.includes('draft') || q.includes('outline') || q.includes('مخطط')) {
        return {
          text: t(
            `Suggested 3-question interactive template outline for ${selectedCourse}: (1) MCQ concept check (5 pts), (2) True/False edge-case verification (5 pts), (3) Written explanation with automated rubric (10 pts). You can author all 3 directly in Assessment Studio.`,
            `مخطط مقترح من ٣ أسئلة لمقرر ${selectedCourse}: (١) اختيار من متعدد (٥ درجات)، (٢) صح أو خطأ (٥ درجات)، (٣) سؤال مقالي بمعيار تصحيح (١٠ درجات). يمكنك إنشاؤه من استوديو القوالب.`
          ),
          source: `${selectedCourse} · ${t('Assessment Template Studio', 'استوديو قوالب التقييم')}`,
          targetPage: 'grading',
          actionLabel: t('Open Template Studio', 'فتح استوديو القوالب'),
        };
      }
      const needs = data.gradeReviews.filter((g) => g.status === 'Needs review');
      const pend = data.petitions.filter((p) => !p.status.toLowerCase().includes('approved'));
      return {
        text: t(
          `There are currently ${needs.length} grade appeal(s) marked "Needs review" and ${pend.length} advisee petition(s) awaiting review.`,
          `يوجد حاليًا ${needs.length} التماس درجات للمراجعة و${pend.length} طلب أكاديمي بانتظار القرار.`
        ),
        source: t('Grading Studio & Academic Affairs', 'سجل التقييمات والشؤون الأكاديمية'),
        targetPage: isStaff ? 'grading' : 'academic-affairs',
        actionLabel: isStaff ? t('Open Grading Studio', 'فتح التقييم') : t('Open Academic Affairs', 'فتح الشؤون الأكاديمية'),
      };
    }

    // 7. Specific Course summary
    if (filterMode === 'Course' && courseObj) {
      return {
        text: t(
          `[${courseObj.id} · ${courseObj.name}] Lecturer: ${courseObj.teacher} · TA: ${courseObj.ta} · Credits: ${courseObj.credits}. Focus: ${courseObj.topic}. Includes ${courseMaterials.length} material(s), ${courseAssignments.length} assignment(s), and ${courseQuizzes.length} quiz/exam item(s). Standing: ${courseObj.grade}% grade, ${courseObj.attendance}% attendance.`,
          `[${courseObj.id} · ${courseObj.nameAr}] المحاضر: ${courseObj.teacher} · المعيد: ${courseObj.ta}. المحور: ${courseObj.topicAr}. يحتوي على ${courseMaterials.length} مادة و${courseAssignments.length} تكليف و${courseQuizzes.length} اختبار.`
        ),
        source: `${courseObj.id} ${t('Course Workspace', 'ملف المقرر')}`,
        targetPage: 'courses',
        courseId: courseObj.id,
        courseTab: 'Overview',
        actionLabel: t(`Open ${courseObj.id} Workspace`, `فتح مقرر ${courseObj.id}`),
      };
    }

    // 8. General workspace summary
    return {
      text: t(
        `Context [${filterMode}]: Grounded across ${data.courses.length} active courses, ${data.assignments.length} interactive assignments, ${data.quizzes.length} quizzes/exams, and ${DIRECTORY_PEOPLE.length} campus directory contacts. Select a specific filter above (Course, Materials, Assignments, Exams, or People & Map) for exact item citations.`,
        `سياق [${filterMode}]: تم البحث في ${data.courses.length} مقررات و${data.assignments.length} تكليفات تفاعلية و${DIRECTORY_PEOPLE.length} جهة اتصال بالدليل. استخدم الفلاتر أعلاه لتحديد عنصر بعينه.`
      ),
      source: t('Cohort Grounded Workspace Index', 'فهرس منصة كوهورت الموثق'),
      targetPage: 'dashboard',
      actionLabel: t('Back to Dashboard', 'العودة للرئيسية'),
    };
  };

  const submitPrompt = (textValue) => {
    const clean = textValue.trim();
    if (!clean) return;
    const scopeParts = [filterMode];
    if (COURSE_SCOPED_MODES.includes(filterMode)) scopeParts.push(selectedCourse);
    if (focusedSpecificItem) {
      scopeParts.push(lang === 'ar' && focusedSpecificItem.titleAr ? focusedSpecificItem.titleAr : focusedSpecificItem.title);
    }
    const filterLabel = scopeParts.join(' · ');
    const reply = buildGroundedReply(clean);

    setData((prev) => ({
      ...prev,
      assistantHistory: [
        ...prev.assistantHistory,
        { id: `u-${Date.now()}`, who: 'user', filter: filterLabel, text: clean },
        {
          id: `a-${Date.now() + 1}`,
          who: 'assistant',
          filter: filterLabel,
          text: reply.text,
          source: reply.source,
          targetPage: reply.targetPage,
          courseId: reply.courseId,
          courseTab: reply.courseTab,
          buildingId: reply.buildingId,
          actionLabel: reply.actionLabel,
        },
      ],
    }));
    setInput('');
  };

  const handleClear = () => {
    setData((prev) => ({
      ...prev,
      assistantHistory: prev.assistantHistory.slice(0, 1),
    }));
    showToast(t('Cleared assistant history', 'تم مسح سجل المساعد الذكي'));
  };

  return (
    <section className="page-enter space-y-5">
      <div className="cohort-card bg-white rounded-3xl p-6 flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <p className="text-[11px] font-bold tracking-widest uppercase text-[#B81104]">
            {t('GROUNDED AI ACADEMIC ASSISTANT', 'المساعد الأكاديمي الذكي الموثق')}
          </p>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-[#1A1715] mt-1">
            {isStaff
              ? t('Faculty & Advising AI Copilot', 'المساعد الذكي لهيئة التدريس والإرشاد')
              : t('General & Filtered Study Assistant', 'مساعد الدراسة العام والمصفّى')}
          </h1>
          <p className="text-sm text-[#6E645D] mt-1">
            {t(
              'Switch between General university answers or Specific Course, Materials, Assignments, Exams, and Campus Directory filters — every reply cites its source.',
              'بدّل بين الأسئلة العامة أو التصفية حسب مقرر أو مادة أو تكليف أو اختبار أو الدليل مع إظهار المصدر الموثق لكل إجابة.'
            )}
          </p>
        </div>

        <button
          type="button"
          onClick={handleClear}
          className="self-start inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-white border border-[#E5DCCF] text-xs font-bold text-[#6E645D] hover:text-[#B81104]"
        >
          <Trash2 className="w-3.5 h-3.5" aria-hidden="true" />
          <span>{t('Reset Chat', 'إعادة ضبط')}</span>
        </button>
      </div>

      {/* General & Specific Filters (#7) */}
      <div className="cohort-card rounded-2xl p-4 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1.5 text-xs font-extrabold text-[#6E645D] me-1">
              <Filter className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
              <span>{t('Scope Filter:', 'نطاق البحث:')}</span>
            </span>
            {FILTER_MODES.map((m) => (
              <button
                key={m.id}
                type="button"
                onClick={() => handleModeChange(m.id)}
                className={`px-3.5 py-1.5 rounded-full text-xs font-bold border transition-colors ${
                  filterMode === m.id
                    ? 'bg-[#B81104] text-[#FFFACD] border-[#B81104]'
                    : 'bg-[#FDFBF7] text-[#6E645D] border-[#E5DCCF] hover:border-[#B81104]/40'
                }`}
              >
                {lang === 'ar' ? m.labelAr : m.labelEn}
              </button>
            ))}
          </div>

          {COURSE_SCOPED_MODES.includes(filterMode) ? (
            <div className="flex flex-wrap items-center gap-2">
              <select
                aria-label={t('Filter by course', 'تصفية حسب المقرر')}
                value={selectedCourse}
                onChange={(e) => handleCourseChange(e.target.value)}
                className="rounded-xl border border-[#E5DCCF] bg-white px-3 py-1.5 text-xs font-bold text-[#1A1715]"
              >
                {data.courses.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.id} · {lang === 'ar' ? c.nameAr : c.name}
                  </option>
                ))}
              </select>

              {specificItems.length > 0 ? (
                <select
                  aria-label={t('Filter specific item', 'تحديد عنصر معين')}
                  value={selectedItemId}
                  onChange={(e) => setSelectedItemId(e.target.value)}
                  className="max-w-[240px] rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/60 px-3 py-1.5 text-xs font-bold text-[#302521]"
                >
                  <option value="ALL">
                    {t(`All ${filterMode} in ${selectedCourse}`, `كل ${filterMode} في ${selectedCourse}`)}
                  </option>
                  {specificItems.map((item) => (
                    <option key={item.id} value={item.id}>
                      {lang === 'ar' && item.titleAr ? item.titleAr : item.title}
                    </option>
                  ))}
                </select>
              ) : null}
            </div>
          ) : null}
        </div>

        {/* Live Context Grounding Strip */}
        <div className="rounded-xl border border-[#EFE7DA] bg-[#FCFBF6] px-3.5 py-2.5 flex flex-wrap items-center justify-between gap-2 text-xs">
          {filterMode === 'General' ? (
            <span className="text-[#6E645D]">
              <strong className="text-[#302521]">{t('Active Scope:', 'النطاق النشط:')}</strong>{' '}
              {t(
                `${data.courses.length} active courses · ${data.assignments.length} assignments · ${data.quizzes.length} quizzes/exams · 7-course registration rules.`,
                `${data.courses.length} مقررات نشطة · ${data.assignments.length} تكليفات · ${data.quizzes.length} اختبارات · لائحة الـ ٧ مقررات.`
              )}
            </span>
          ) : filterMode === 'Directory' ? (
            <span className="inline-flex items-center gap-1.5 text-[#6E645D]">
              <MapPin className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
              <span>
                <strong className="text-[#302521]">{t('Directory & Map Scope:', 'نطاق الدليل والخريطة:')}</strong>{' '}
                {t(
                  `${DIRECTORY_PEOPLE.length} indexed profiles across ${CAMPUS_LOCATIONS.length} campus complexes.`,
                  `${DIRECTORY_PEOPLE.length} ملفًا عبر ${CAMPUS_LOCATIONS.length} مبانٍ جامعية.`
                )}
              </span>
            </span>
          ) : (
            <div className="flex flex-wrap items-center gap-3 text-[#6E645D]">
              <span className="inline-flex items-center gap-1.5 font-bold text-[#302521]">
                {filterMode === 'Assignments' ? (
                  <ClipboardList className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
                ) : filterMode === 'Exams' ? (
                  <HelpCircle className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
                ) : (
                  <BookOpen className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
                )}
                <span>
                  {courseObj?.id} · {lang === 'ar' ? courseObj?.nameAr : courseObj?.name}
                </span>
              </span>
              <span>
                {courseObj?.teacher} · TA {courseObj?.ta}
              </span>
              {focusedSpecificItem ? (
                <span className="rounded-full bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-0.5 text-[11px] font-bold text-[#960D03]">
                  {t('Pinned:', 'محدد:')} {lang === 'ar' && focusedSpecificItem.titleAr ? focusedSpecificItem.titleAr : focusedSpecificItem.title}
                </span>
              ) : null}
            </div>
          )}
        </div>
      </div>

      {/* Conversation History */}
      <div className="cohort-card rounded-2xl p-4 sm:p-5 space-y-4">
        <div className="space-y-3 max-h-[380px] overflow-y-auto pe-1">
          {data.assistantHistory.map((msg) => (
            <div
              key={msg.id}
              className={`flex ${msg.who === 'user' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-2xl rounded-2xl px-4 py-3 text-sm space-y-1.5 ${
                  msg.who === 'user'
                    ? 'bg-[#B81104] text-[#FFFACD]'
                    : 'bg-[#FDFBF7] border border-[#E5DCCF] text-[#1A1715]'
                }`}
              >
                <div className="flex items-center justify-between gap-3 text-[11px] font-bold opacity-85">
                  <span className="inline-flex items-center gap-1">
                    {msg.who === 'assistant' && <Sparkles className="w-3 h-3 text-[#B81104]" aria-hidden="true" />}
                    <span>{msg.who === 'user' ? t('You', 'أنت') : 'Cohort AI'}</span>
                  </span>
                  <span
                    className={`px-2 py-0.5 rounded-full ${
                      msg.who === 'user' ? 'bg-white/15 text-[#FFFACD]' : 'bg-[#EFE7DA] text-[#302521]'
                    }`}
                  >
                    {msg.filter}
                  </span>
                </div>
                <p className="leading-relaxed">{msg.text}</p>
                {msg.source ? (
                  <div className="pt-1.5 flex flex-wrap items-center justify-between gap-2 text-[11px] text-[#6E645D] border-t border-[#EFE7DA]/80">
                    <span className="inline-flex items-center gap-1 font-semibold">
                      <BookOpen className="w-3 h-3 text-[#B81104]" aria-hidden="true" />
                      <span>
                        {t('Source:', 'المصدر:')} {msg.source}
                      </span>
                    </span>
                    {msg.targetPage ? (
                      <button
                        type="button"
                        onClick={() =>
                          navigate(msg.targetPage, {
                            courseId: msg.courseId || selectedCourse,
                            courseTab: msg.courseTab,
                            buildingId: msg.buildingId,
                          })
                        }
                        className="inline-flex items-center gap-1 rounded-lg bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-1 text-[11px] font-bold text-[#960D03] hover:bg-[#FFF3B0]"
                      >
                        <span>{msg.actionLabel || t('Open source', 'فتح المصدر')}</span>
                        <ExternalLink className="w-3 h-3" aria-hidden="true" />
                      </button>
                    ) : null}
                  </div>
                ) : null}
              </div>
            </div>
          ))}
        </div>

        {/* Quick prompts */}
        <div className="flex flex-wrap gap-2 pt-2 border-t border-[#EFE7DA]">
          {quickPrompts.map((promptText) => (
            <button
              key={promptText}
              type="button"
              onClick={() => submitPrompt(promptText)}
              className="px-3 py-1.5 rounded-full bg-[#FFFACD]/70 hover:bg-[#FFFACD] border border-[#B81104]/20 text-xs font-semibold text-[#1A1715] transition-colors text-start"
            >
              {promptText}
            </button>
          ))}
        </div>

        {/* Input Composer */}
        <form
          onSubmit={(e) => {
            e.preventDefault();
            submitPrompt(input);
          }}
          className="flex items-center gap-2"
        >
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            aria-label={t('Ask Cohort AI Assistant', 'اسأل مساعد كوهورت الذكي')}
            placeholder={t(
              `Ask a ${filterMode.toLowerCase()} academic question...`,
              'اكتب سؤالك الأكاديمي هنا...'
            )}
            className="flex-1 rounded-2xl border border-[#E5DCCF] bg-white px-4 py-2.5 text-sm text-[#1A1715]"
          />
          <button
            type="submit"
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-2xl bg-[#B81104] text-[#FFFACD] text-sm font-bold hover:bg-[#960D03] transition-colors"
          >
            <Send className="w-4 h-4" aria-hidden="true" />
            <span>{t('Ask', 'إرسال')}</span>
          </button>
        </form>
      </div>
    </section>
  );
}
