import React, { useMemo, useState } from 'react';
import {
  Award,
  Bell,
  BookOpen,
  CheckCircle2,
  CheckSquare,
  ExternalLink,
  FilePlus2,
  FileText,
  HelpCircle,
  MapPin,
  MessageSquare,
  Play,
  Plus,
  Search,
  Send,
  Sparkles,
  Users,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { DIRECTORY_PEOPLE } from '../../data/seedData';
import { StatusBadge } from '../common/StatusBadge';
import { WaygroundBuilder, WaygroundPlayer } from '../common/WaygroundTemplateStudio';

const COURSE_TABS = [
  { id: 'Overview', en: 'Overview', ar: 'نظرة عامة', Icon: BookOpen },
  { id: 'Materials', en: 'Materials', ar: 'المواد الدراسية', Icon: FileText },
  { id: 'Assignments', en: 'Assignments', ar: 'التكليفات', Icon: CheckSquare },
  { id: 'Quizzes & Exams', en: 'Quizzes & Exams', ar: 'الاختبارات والامتحانات', Icon: HelpCircle },
  { id: 'Grades', en: 'Grades', ar: 'الدرجات', Icon: Award },
  { id: 'Attendance', en: 'Attendance', ar: 'الحضور', Icon: Users },
  { id: 'Announcements', en: 'Announcements', ar: 'الإعلانات', Icon: Bell },
  { id: 'Discussion', en: 'Discussion', ar: 'المناقشة', Icon: MessageSquare },
];

const ATTENDANCE_OPTIONS = ['Present', 'Late', 'Excused', 'Absent'];

function attendanceBadgeProps(val, t) {
  switch (val) {
    case 'Present':
      return { status: 'Approved', label: t('Present', 'حاضر') };
    case 'Late':
      return { status: 'Pending', label: t('Late', 'متأخر') };
    case 'Excused':
      return { status: 'Scheduled', label: t('Excused', 'بعذر') };
    default:
      return { status: 'Rejected', label: t('Absent', 'غائب') };
  }
}

export function CoursesPage() {
  const {
    role,
    lang,
    t,
    profile,
    data,
    setData,
    selectedCourseId,
    setSelectedCourseId,
    courseTab,
    setCourseTab,
    navigate,
    showToast,
  } = useCohort();

  const isStaff = role === 'Academic Staff';
  const course = data.courses.find((c) => c.id === selectedCourseId) || data.courses[0];

  // Materials state
  const [matFolder, setMatFolder] = useState('All');
  const [matQuery, setMatQuery] = useState('');
  const [newMatTitle, setNewMatTitle] = useState('');
  const [newMatFolder, setNewMatFolder] = useState('Lectures');
  const [newMatNotes, setNewMatNotes] = useState('');

  // Assignments state
  const [submissionInputs, setSubmissionInputs] = useState({});
  const [activeAsgId, setActiveAsgId] = useState(null);
  const [showAsgBuilder, setShowAsgBuilder] = useState(true);

  // Quizzes inline attempt & builder state
  const [activeQuizId, setActiveQuizId] = useState(null);
  const [showQuizBuilder, setShowQuizBuilder] = useState(false);

  // Attendance session selector state (Staff view)
  const [attendanceSession, setAttendanceSession] = useState('Week 8 · Lecture');

  // Grades appeal state
  const [appealTarget, setAppealTarget] = useState('');
  const [appealNote, setAppealNote] = useState('');

  // Course announcement composer state
  const [courseAnnTitle, setCourseAnnTitle] = useState('');
  const [courseAnnBody, setCourseAnnBody] = useState('');

  // Discussion message composer state
  const [chatDraft, setChatDraft] = useState('');

  const courseMaterials = useMemo(
    () =>
      data.materials.filter((m) => {
        if (m.course !== course.id) return false;
        const folderMatch = matFolder === 'All' || m.folder === matFolder;
        const q = matQuery.trim().toLowerCase();
        const queryMatch =
          !q || m.title.toLowerCase().includes(q) || m.notes.toLowerCase().includes(q);
        return folderMatch && queryMatch;
      }),
    [course.id, data.materials, matFolder, matQuery]
  );

  const courseAssignments = useMemo(
    () => data.assignments.filter((a) => a.course === course.id),
    [course.id, data.assignments]
  );

  const courseQuizzes = useMemo(
    () => data.quizzes.filter((q) => q.course === course.id),
    [course.id, data.quizzes]
  );

  const courseGrades = useMemo(
    () =>
      data.gradeReviews.filter(
        (g) => g.course === course.id && (isStaff || g.student === 'Alex Chen')
      ),
    [course.id, data.gradeReviews, isStaff]
  );

  const courseAnnouncements = useMemo(
    () =>
      data.announcements.filter(
        (ann) => ann.course === course.id || ann.audience === 'All'
      ),
    [course.id, data.announcements]
  );

  const threadId = `course-${course.id}`;
  const discussionMessages = useMemo(() => {
    const existing = data.chatThreads[threadId];
    if (existing && existing.length > 0) return existing;
    return [
      {
        id: `init-${threadId}`,
        sender: course.teacher,
        senderId: 'staff-init',
        senderRole: 'Academic Staff',
        text: t(
          `Welcome to the ${course.id} course discussion channel. Ask questions or coordinate lab sections here.`,
          `مرحبًا بكم في قناة مناقشة مقرر ${course.id}. يمكنكم طرح الأسئلة والتنسيق للمعامل هنا.`
        ),
        time: '09:00',
      },
    ];
  }, [course.id, course.teacher, data.chatThreads, t, threadId]);

  const studentRoster = useMemo(
    () => DIRECTORY_PEOPLE.filter((p) => p.category === 'Student'),
    []
  );

  const courseAttendanceMap = useMemo(() => {
    const saved = data.attendanceLog?.[course.id];
    if (saved) return saved;
    return {
      'p-alex': 'Present',
      'p-sara': 'Present',
      'p-omar': 'Late',
      'p-nour': 'Present',
    };
  }, [course.id, data.attendanceLog]);

  const lecturerMeta = useMemo(
    () => DIRECTORY_PEOPLE.find((p) => p.name === course.teacher),
    [course.teacher]
  );
  const taMeta = useMemo(
    () => DIRECTORY_PEOPLE.find((p) => p.name === course.ta),
    [course.ta]
  );

  const handlePublishMaterial = (e) => {
    e.preventDefault();
    const cleanTitle = newMatTitle.trim();
    if (!cleanTitle || !newMatNotes.trim()) {
      showToast(t('Enter material title and study notes.', 'أدخل عنوان المادة والملاحظات.'));
      return;
    }
    const existingSameTitle = data.materials.filter(
      (m) => m.course === course.id && m.title.toLowerCase() === cleanTitle.toLowerCase()
    );
    const nextVersion =
      existingSameTitle.length > 0
        ? Math.max(...existingSameTitle.map((m) => m.version || 1)) + 1
        : 1;

    const newItem = {
      id: `mat-${Date.now()}`,
      course: course.id,
      title: cleanTitle,
      folder: newMatFolder,
      version: nextVersion,
      date: new Date().toISOString().slice(0, 10),
      notes: newMatNotes.trim(),
    };
    setData((prev) => ({
      ...prev,
      materials: [newItem, ...prev.materials],
    }));
    setNewMatTitle('');
    setNewMatNotes('');
    showToast(
      t(`Published "${cleanTitle}" (v${nextVersion}).`, `تم نشر "${cleanTitle}" (الإصدار ${nextVersion}).`)
    );
  };

  const handleSubmitAssignment = (asgId) => {
    const note = (submissionInputs[asgId] || '').trim() || 'Submitted online via Cohort LMS';
    setData((prev) => ({
      ...prev,
      assignments: prev.assignments.map((a) =>
        a.id === asgId
          ? {
              ...a,
              submitted: true,
              status: 'Submitted',
              submittedAt: 'Just now',
              submissionNote: note,
            }
          : a
      ),
    }));
    showToast(t('Assignment submitted successfully.', 'تم تسليم التكليف بنجاح.'));
  };

  const handleToggleQuizStatus = (quizId) => {
    setData((prev) => ({
      ...prev,
      quizzes: prev.quizzes.map((q) =>
        q.id === quizId
          ? { ...q, status: q.status === 'Published' ? 'Draft' : 'Published' }
          : q
      ),
    }));
    showToast(t('Assessment status updated.', 'تم تحديث حالة التقييم.'));
  };

  const handleUpdateCourseGradeRow = (id, patch) => {
    setData((prev) => ({
      ...prev,
      gradeReviews: prev.gradeReviews.map((g) => (g.id === id ? { ...g, ...patch } : g)),
    }));
  };

  const handleStudentCourseAppeal = (e) => {
    e.preventDefault();
    if (!appealTarget.trim() || !appealNote.trim()) {
      showToast(t('Specify the assessment name and appeal details.', 'حدد التقييم وسبب الالتماس.'));
      return;
    }
    setData((prev) => ({
      ...prev,
      gradeReviews: [
        {
          id: `gr-${Date.now()}`,
          student: profile.name,
          course: course.id,
          assessment: appealTarget.trim(),
          score: course.grade,
          status: 'Needs review',
          feedback: `Appeal: ${appealNote.trim()}`,
        },
        ...prev.gradeReviews,
      ],
    }));
    setAppealTarget('');
    setAppealNote('');
    showToast(t('Grade appeal sent to instructor.', 'تم إرسال طلب مراجعة الدرجة للمحاضر.'));
  };

  const handleRosterStatusChange = (studentId, nextStatus) => {
    setData((prev) => ({
      ...prev,
      attendanceLog: {
        ...(prev.attendanceLog || {}),
        [course.id]: {
          ...courseAttendanceMap,
          [studentId]: nextStatus,
        },
      },
    }));
  };

  const handleMarkAllPresent = () => {
    const nextMap = {};
    studentRoster.forEach((st) => {
      nextMap[st.id] = 'Present';
    });
    setData((prev) => ({
      ...prev,
      attendanceLog: {
        ...(prev.attendanceLog || {}),
        [course.id]: nextMap,
      },
    }));
    showToast(
      t(
        `Marked all ${studentRoster.length} students Present for ${attendanceSession}.`,
        `تم تسجيل حضور جميع الطلاب لـ ${attendanceSession}.`
      )
    );
  };

  const handlePostCourseAnnouncement = (e) => {
    e.preventDefault();
    if (!courseAnnTitle.trim() || !courseAnnBody.trim()) {
      showToast(t('Enter headline and message body.', 'أدخل عنوان الإعلان ونصه.'));
      return;
    }
    setData((prev) => ({
      ...prev,
      announcements: [
        {
          id: `ann-${Date.now()}`,
          title: courseAnnTitle.trim(),
          titleAr: courseAnnTitle.trim(),
          audience: course.id,
          course: course.id,
          date: new Date().toISOString().slice(0, 10),
          body: courseAnnBody.trim(),
        },
        ...prev.announcements,
      ],
    }));
    setCourseAnnTitle('');
    setCourseAnnBody('');
    showToast(t(`Posted notice to ${course.id}.`, `تم نشر الإعلان لمقرر ${course.id}.`));
  };

  const handleSendDiscussion = (e) => {
    e.preventDefault();
    const clean = chatDraft.trim();
    if (!clean) return;
    const nowTime = new Date().toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
    });
    const nextMsg = {
      id: `cmsg-${Date.now()}`,
      sender: lang === 'ar' && profile.nameAr ? profile.nameAr : profile.name,
      senderId: profile.id,
      senderRole: role,
      text: clean,
      time: nowTime,
    };
    setData((prev) => ({
      ...prev,
      chatThreads: {
        ...prev.chatThreads,
        [threadId]: [...(prev.chatThreads[threadId] || discussionMessages), nextMsg],
      },
    }));
    setChatDraft('');
  };

  return (
    <section className="page-enter space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {t('COURSE WORKSPACE · 8 INTEGRATED TABS', 'مساحة المقرر · ٨ تبويبات متكاملة')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {course.id} · {lang === 'ar' ? course.nameAr : course.name}
          </h1>
          <p className="mt-1 text-sm text-[#6E645D]">
            {course.teacher} · TA: {course.ta} · {course.section} · {course.credits} {t('Credits', 'ساعات معتمدة')}
          </p>
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="course-switcher" className="text-xs font-semibold text-[#6E645D]">
            {t('Switch Course:', 'تغيير المقرر:')}
          </label>
          <select
            id="course-switcher"
            value={course.id}
            onChange={(e) => {
              setSelectedCourseId(e.target.value);
              setActiveQuizId(null);
              setActiveAsgId(null);
            }}
            className="min-h-[42px] rounded-xl border border-[#E8E3D9] bg-white px-3 text-xs font-bold text-[#302521]"
          >
            {data.courses.map((c) => (
              <option key={c.id} value={c.id}>
                {c.id} · {lang === 'ar' ? c.nameAr : c.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* 8-Tab Course Bar (#2) */}
      <div
        role="tablist"
        aria-label={t('Course Workspace Sections', 'أقسام المقرر')}
        className="flex gap-1.5 overflow-x-auto rounded-2xl border border-[#E8E3D9] bg-white p-2"
      >
        {COURSE_TABS.map((tab) => {
          const Icon = tab.Icon;
          const active = courseTab === tab.id;
          return (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => setCourseTab(tab.id)}
              className={`inline-flex min-h-[40px] shrink-0 items-center gap-1.5 rounded-xl px-3.5 py-2 text-xs font-semibold transition ${
                active
                  ? 'bg-[#FFFACD] text-[#B81104] shadow-xs'
                  : 'text-[#6E645D] hover:bg-[#FCFBF6] hover:text-[#302521]'
              }`}
            >
              <Icon className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{lang === 'ar' ? tab.ar : tab.en}</span>
            </button>
          );
        })}
      </div>

      {/* Active Tab Content */}
      <div className="cohort-card p-6">
        {courseTab === 'Overview' ? (
          <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
            <div className="md:col-span-2 space-y-5">
              <div>
                <h2 className="text-lg font-bold text-[#302521]">{t('Course Overview', 'نظرة عامة على المقرر')}</h2>
                <p className="mt-1.5 text-sm text-[#6E645D] leading-relaxed">
                  {lang === 'ar' ? course.topicAr : course.topic}
                </p>
              </div>

              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <div className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
                  <span className="text-[11px] font-semibold text-[#6E645D]">{t('Grade Average', 'متوسط الدرجة')}</span>
                  <p className="mt-1 text-xl font-extrabold text-[#302521] tabular-nums">{course.grade}%</p>
                </div>
                <div className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
                  <span className="text-[11px] font-semibold text-[#6E645D]">{t('Attendance', 'نسبة الحضور')}</span>
                  <p className="mt-1 text-xl font-extrabold text-[#16845B] tabular-nums">{course.attendance}%</p>
                </div>
                <div className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
                  <span className="text-[11px] font-semibold text-[#6E645D]">{t('Enrolled', 'المسجلون')}</span>
                  <p className="mt-1 text-xl font-extrabold text-[#302521] tabular-nums">
                    {course.enrolled}/{course.capacity}
                  </p>
                </div>
                <div className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
                  <span className="text-[11px] font-semibold text-[#6E645D]">{t('Credit Hours', 'الساعات المعتمدة')}</span>
                  <p className="mt-1 text-xl font-extrabold text-[#B81104] tabular-nums">{course.credits} Cr</p>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="rounded-xl border border-[#E8E3D9] bg-white p-4 space-y-1.5">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[#B81104]">
                    {t('Course Lecturer', 'محاضر المقرر')}
                  </span>
                  <p className="text-sm font-bold text-[#302521]">{course.teacher}</p>
                  <p className="text-xs text-[#6E645D]">
                    {lecturerMeta ? `${lecturerMeta.room} · ${lecturerMeta.officeHours}` : 'Eng Bldg · Office Hours Posted'}
                  </p>
                  <button
                    type="button"
                    onClick={() => navigate('map', { buildingId: lecturerMeta?.buildingId || 'Engineering' })}
                    className="mt-1 inline-flex items-center gap-1 text-xs font-bold text-[#B81104] hover:underline"
                  >
                    <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>{t('Locate on Campus Map', 'الموقع على الخريطة')}</span>
                  </button>
                </div>

                <div className="rounded-xl border border-[#E8E3D9] bg-white p-4 space-y-1.5">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[#B81104]">
                    {t('Teaching Assistant (TA)', 'المعيد المعاون')}
                  </span>
                  <p className="text-sm font-bold text-[#302521]">{course.ta}</p>
                  <p className="text-xs text-[#6E645D]">
                    {taMeta ? `${taMeta.room} · ${taMeta.officeHours}` : 'TA Wing · Lab Support'}
                  </p>
                  <button
                    type="button"
                    onClick={() => navigate('map', { buildingId: taMeta?.buildingId || 'TA Wing' })}
                    className="mt-1 inline-flex items-center gap-1 text-xs font-bold text-[#B81104] hover:underline"
                  >
                    <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>{t('Locate TA Room', 'غرفة المعيد على الخريطة')}</span>
                  </button>
                </div>
              </div>
            </div>

            <div className="cohort-lemon-panel rounded-xl p-4 space-y-3 h-fit">
              <h3 className="text-sm font-bold text-[#B81104]">
                {isStaff ? t('Staff Teaching Tools', 'أدوات هيئة التدريس') : t('Course Quick Actions', 'إجراءات سريعة للمقرر')}
              </h3>
              <button
                type="button"
                onClick={() => setCourseTab('Discussion')}
                className="w-full rounded-xl bg-[#B81104] px-3 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
              >
                {t('Open Course Group Chat', 'فتح محادثة المقرر الجماعية')}
              </button>
              <button
                type="button"
                onClick={() => navigate('assistant')}
                className="w-full rounded-xl border border-[#E9DBA9] bg-white px-3 py-2 text-xs font-bold text-[#302521]"
              >
                {t('Ask AI Assistant about ', 'اسأل المساعد الذكي عن ') + course.id}
              </button>
              {isStaff ? (
                <button
                  type="button"
                  onClick={() => navigate('grading')}
                  className="w-full rounded-xl border border-[#E9DBA9] bg-white px-3 py-2 text-xs font-bold text-[#B81104]"
                >
                  {t('Open Grading & Template Studio', 'فتح استوديو التقييم والقوالب')}
                </button>
              ) : null}
            </div>
          </div>
        ) : courseTab === 'Materials' ? (
          <div className="space-y-5">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <h2 className="text-lg font-bold text-[#302521]">{t('Course Materials', 'المواد الدراسية')}</h2>
              <div className="flex flex-wrap items-center gap-2">
                <div className="relative">
                  <Search className="h-3.5 w-3.5 text-[#6E645D] absolute start-3 top-1/2 -translate-y-1/2" aria-hidden="true" />
                  <input
                    type="text"
                    value={matQuery}
                    onChange={(e) => setMatQuery(e.target.value)}
                    aria-label={t('Search course materials', 'البحث في المواد الدراسية')}
                    placeholder={t('Filter notes or topics...', 'بحث في العناوين أو الملاحظات...')}
                    className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] ps-8 pe-3 py-1.5 text-xs text-[#302521]"
                  />
                </div>
                {['All', 'Lectures', 'Labs', 'References'].map((folder) => (
                  <button
                    key={folder}
                    type="button"
                    onClick={() => setMatFolder(folder)}
                    className={`rounded-full border px-3 py-1 text-xs font-bold transition ${
                      matFolder === folder
                        ? 'border-[#B81104] bg-[#B81104] text-[#FFFACD]'
                        : 'border-[#E8E3D9] bg-white text-[#6E645D]'
                    }`}
                  >
                    {folder}
                  </button>
                ))}
              </div>
            </div>

            {isStaff ? (
              <form
                onSubmit={handlePublishMaterial}
                className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/35 p-4 space-y-3"
              >
                <div className="flex items-center gap-2">
                  <FilePlus2 className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                  <h3 className="text-xs font-extrabold uppercase tracking-wider text-[#B81104]">
                    {t('Publish or Update Course Material', 'نشر أو تحديث مادة دراسية')}
                  </h3>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
                  <input
                    type="text"
                    value={newMatTitle}
                    onChange={(e) => setNewMatTitle(e.target.value)}
                    placeholder={t('Title (reusing title bumps version)...', 'العنوان (إعادة الاسم ترفع رقم الإصدار)...')}
                    className="sm:col-span-2 rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                  />
                  <select
                    aria-label={t('Material folder', 'المجلد')}
                    value={newMatFolder}
                    onChange={(e) => setNewMatFolder(e.target.value)}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs font-bold text-[#302521]"
                  >
                    <option value="Lectures">Lectures</option>
                    <option value="Labs">Labs</option>
                    <option value="References">References</option>
                  </select>
                </div>
                <textarea
                  rows={2}
                  value={newMatNotes}
                  onChange={(e) => setNewMatNotes(e.target.value)}
                  placeholder={t('Key concepts or summary notes...', 'ملخص المفاهيم أو الملاحظات...')}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                />
                <button
                  type="submit"
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
                >
                  <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('Publish Material', 'نشر المادة')}</span>
                </button>
              </form>
            ) : null}

            {courseMaterials.length ? (
              <div className="space-y-3">
                {courseMaterials.map((m) => (
                  <div key={m.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-2">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <h3 className="text-sm font-bold text-[#302521]">{m.title}</h3>
                      <div className="flex items-center gap-2">
                        <span className="text-[11px] text-[#6E645D] tabular-nums">{m.date}</span>
                        <span className="rounded bg-[#FFFACD] px-2.5 py-0.5 text-[11px] font-bold text-[#B81104]">
                          {m.folder} · v{m.version}
                        </span>
                      </div>
                    </div>
                    <p className="text-xs text-[#6E645D] leading-relaxed">{m.notes}</p>
                    <button
                      type="button"
                      onClick={() => navigate('assistant')}
                      className="inline-flex items-center gap-1 text-xs font-bold text-[#B81104] hover:underline"
                    >
                      <Sparkles className="h-3.5 w-3.5" aria-hidden="true" />
                      <span>{t('Explain with AI Assistant', 'اشرح بالمساعد الذكي')}</span>
                    </button>
                  </div>
                ))}
              </div>
            ) : (
              <p className="rounded-xl border border-dashed border-[#E8E3D9] p-6 text-center text-sm text-[#6E645D]">
                {t('No materials posted in this filter for ', 'لا توجد مواد منشورة ضمن هذا الفلتر لمقرر ') + course.id}
              </p>
            )}
          </div>
        ) : courseTab === 'Assignments' ? (
          <div className="space-y-5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-lg font-bold text-[#302521]">{t('Course Assignments', 'تكليفات المقرر')}</h2>
              {isStaff ? (
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setShowAsgBuilder((prev) => !prev)}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-3.5 py-1.5 text-xs font-bold text-[#FFFACD]"
                  >
                    <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>
                      {showAsgBuilder
                        ? t('Hide Assignment Studio', 'إخفاء منشئ التكليف')
                        : t('Create Assignment Template', 'إنشاء قالب تكليف')}
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => navigate('grading')}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-[#FFFACD] border border-[#E9DBA9] px-3 py-1.5 text-xs font-bold text-[#B81104]"
                  >
                    <span>{t('Open Grading Queue', 'فتح سجل التصحيح')}</span>
                    <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                </div>
              ) : null}
            </div>

            {isStaff && showAsgBuilder ? (
              <WaygroundBuilder
                defaultTargetType="assignment"
                allowTargetSwitch={false}
                fixedCourseId={course.id}
                onSaved={({ id }) => {
                  if (id && id !== 'new') setActiveAsgId(id);
                }}
              />
            ) : null}

            {courseAssignments.length ? (
              <div className="space-y-3">
                {courseAssignments.map((a) => {
                  const isOpen = activeAsgId === a.id;
                  const qCount = (a.questions || []).length;
                  return (
                    <div key={a.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-3">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <h3 className="text-sm font-bold text-[#302521]">{lang === 'ar' ? a.titleAr : a.title}</h3>
                            <span className="rounded bg-[#FFFACD] px-2 py-0.5 text-[11px] font-bold text-[#960D03]">
                              {a.templateType}
                            </span>
                            {qCount > 0 ? (
                              <span className="rounded bg-white border border-[#E8E3D9] px-2 py-0.5 text-[11px] font-bold text-[#6E645D] tabular-nums">
                                {qCount} {t('question(s)', 'أسئلة')}
                              </span>
                            ) : null}
                          </div>
                          <p className="mt-1 text-xs text-[#6E645D]">{a.instructions}</p>
                          <p className="mt-1 text-[11px] font-semibold text-[#6E645D] tabular-nums">
                            {t('Due:', 'موعد التسليم:')} {a.due}
                            {a.grade ? ` · ${t('Score:', 'الدرجة:')} ${a.grade}/100` : ''}
                          </p>
                        </div>

                        <div className="flex flex-wrap items-center gap-2">
                          <StatusBadge status={a.status} />
                          {qCount > 0 ? (
                            <button
                              type="button"
                              onClick={() => setActiveAsgId(isOpen ? null : a.id)}
                              className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-3.5 py-1.5 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
                            >
                              <Play className="h-3.5 w-3.5" aria-hidden="true" />
                              <span>
                                {isOpen
                                  ? t('Hide Assignment Questions', 'إخفاء الأسئلة')
                                  : isStaff
                                    ? t('Preview Questions', 'معاينة الأسئلة')
                                    : a.submitted
                                      ? t('Review Interactive Work', 'مراجعة الإجابات')
                                      : t('Start Interactive Assignment', 'بدء التكليف التفاعلي')}
                              </span>
                            </button>
                          ) : null}
                        </div>
                      </div>

                      {isOpen && qCount > 0 ? (
                        <WaygroundPlayer item={a} itemType="assignment" isStaff={isStaff} />
                      ) : !isStaff && !a.submitted && qCount === 0 ? (
                        <div className="flex flex-col sm:flex-row gap-2 pt-2 border-t border-[#E8E3D9]">
                          <input
                            type="text"
                            value={submissionInputs[a.id] || ''}
                            onChange={(e) =>
                              setSubmissionInputs((prev) => ({ ...prev, [a.id]: e.target.value }))
                            }
                            aria-label={t(`Submission note for ${a.title}`, `ملاحظة التسليم لـ ${a.title}`)}
                            placeholder={t('Paste repository link, lab answer summary, or upload note...', 'أدخل رابط الحل أو ملخص التسليم...')}
                            className="flex-1 rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                          />
                          <button
                            type="button"
                            onClick={() => handleSubmitAssignment(a.id)}
                            className="inline-flex items-center justify-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
                          >
                            <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                            <span>{t('Submit Now', 'تسليم الآن')}</span>
                          </button>
                        </div>
                      ) : null}

                      {a.submitted && a.submissionNote ? (
                        <p className="rounded-lg bg-white border border-[#E8E3D9] px-3 py-2 text-xs text-[#16845B] font-semibold">
                          {t('Submitted:', 'تم التسليم:')} {a.submissionNote} ({a.submittedAt || t('Recorded', 'مسجل')})
                        </p>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="rounded-xl border border-dashed border-[#E8E3D9] p-6 text-center text-sm text-[#6E645D]">
                {t('No assignments posted yet for ', 'لا توجد تكليفات مضافة بعد لمقرر ') + course.id}
              </p>
            )}
          </div>
        ) : courseTab === 'Quizzes & Exams' ? (
          <div className="space-y-5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-lg font-bold text-[#302521]">{t('Quizzes & Exams', 'الاختبارات والامتحانات')}</h2>
              {isStaff ? (
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setShowQuizBuilder((prev) => !prev)}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-3.5 py-2 text-xs font-bold text-[#FFFACD]"
                  >
                    <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>
                      {showQuizBuilder
                        ? t('Hide Quiz Builder', 'إخفاء منشئ الاختبار')
                        : t('Create Quiz Template', 'إنشاء قالب اختبار')}
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => navigate('grading')}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-[#FFFACD] border border-[#E9DBA9] px-3 py-2 text-xs font-bold text-[#960D03]"
                  >
                    <span>{t('Open Full Studio', 'الاستوديو الكامل')}</span>
                    <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                </div>
              ) : null}
            </div>

            {isStaff && showQuizBuilder ? (
              <WaygroundBuilder
                defaultTargetType="quiz"
                allowTargetSwitch={false}
                fixedCourseId={course.id}
                onSaved={({ id }) => {
                  if (id && id !== 'new') setActiveQuizId(id);
                }}
              />
            ) : null}

            {courseQuizzes.length ? (
              <div className="space-y-4">
                {courseQuizzes.map((q) => {
                  const isAttemptOpen = activeQuizId === q.id;
                  return (
                    <div key={q.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-3">
                      <div className="flex flex-wrap items-center justify-between gap-3">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <h3 className="text-sm font-bold text-[#302521]">
                              {lang === 'ar' ? q.titleAr : q.title}
                            </h3>
                            <StatusBadge status={q.status} />
                          </div>
                          <p className="mt-1 text-xs text-[#6E645D] tabular-nums">
                            {q.kind} · {q.duration} {t('min', 'دقيقة')} · {q.date}
                            {q.room ? ` · ${q.room}` : ''} · {(q.questions || []).length}{' '}
                            {t('question(s)', 'أسئلة')}
                          </p>
                        </div>

                        <div className="flex flex-wrap items-center gap-2">
                          {isStaff ? (
                            <button
                              type="button"
                              onClick={() => handleToggleQuizStatus(q.id)}
                              className="rounded-xl border border-[#E8E3D9] bg-white px-3 py-1.5 text-xs font-bold text-[#302521] hover:border-[#B81104]"
                            >
                              {q.status === 'Published'
                                ? t('Move to Draft', 'إرجاع لمسودة')
                                : t('Publish Quiz', 'نشر الاختبار')}
                            </button>
                          ) : null}
                          {q.questions?.length ? (
                            <button
                              type="button"
                              onClick={() => setActiveQuizId(isAttemptOpen ? null : q.id)}
                              className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-3.5 py-1.5 text-xs font-bold text-[#FFFACD]"
                            >
                              <Play className="h-3.5 w-3.5" aria-hidden="true" />
                              <span>
                                {isAttemptOpen
                                  ? t('Hide Questions', 'إخفاء الأسئلة')
                                  : isStaff
                                    ? t('Preview Questions', 'معاينة الأسئلة')
                                    : t('Start / Practice Quiz', 'بدء / معاينة الاختبار')}
                              </span>
                            </button>
                          ) : null}
                        </div>
                      </div>

                      {isAttemptOpen && q.questions?.length ? (
                        <WaygroundPlayer item={q} itemType="quiz" isStaff={isStaff} />
                      ) : null}
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="rounded-xl border border-dashed border-[#E8E3D9] p-6 text-center text-sm text-[#6E645D]">
                {t('No quizzes or exams scheduled yet for ', 'لا توجد اختبارات مجدولة حاليًا لمقرر ') + course.id}
              </p>
            )}
          </div>
        ) : courseTab === 'Grades' ? (
          <div className="space-y-5">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="text-lg font-bold text-[#302521]">
                  {isStaff
                    ? t(`${course.id} Gradebook & Review Queue`, `سجل درجات ومراجعات ${course.id}`)
                    : t(`${course.id} Grades & Appeals`, `درجات والتماسات ${course.id}`)}
                </h2>
                <p className="text-xs text-[#6E645D]">
                  {t('Standing course average:', 'متوسط المقرر الحالي:')}{' '}
                  <strong className="text-[#B81104] tabular-nums">{course.grade}%</strong>
                </p>
              </div>
              {isStaff ? (
                <button
                  type="button"
                  onClick={() => navigate('grading')}
                  className="rounded-xl bg-[#B81104] px-3.5 py-2 text-xs font-bold text-[#FFFACD]"
                >
                  {t('Open Full Grading Studio', 'فتح استوديو التقييم الكامل')}
                </button>
              ) : null}
            </div>

            {/* Coursework & Interactive Assessment Breakdown */}
            <div className="rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h3 className="text-xs font-extrabold uppercase tracking-wider text-[#B81104]">
                  {t('Coursework & Interactive Assessment Breakdown', 'تفاصيل أعمال السنة والتقييمات التفاعلية')}
                </h3>
                <span className="text-[11px] font-semibold text-[#6E645D] tabular-nums">
                  {courseAssignments.length} {t('Assignments', 'تكليفات')} · {courseQuizzes.length} {t('Quizzes/Exams', 'اختبارات')}
                </span>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                {courseAssignments.map((asg) => {
                  const pts = (asg.questions || []).reduce((sum, q) => sum + (q.points || 0), 0);
                  return (
                    <div
                      key={asg.id}
                      className="flex items-center justify-between gap-2 rounded-xl border border-[#E8E3D9] bg-white px-3.5 py-2.5"
                    >
                      <div className="min-w-0">
                        <p className="text-xs font-bold text-[#302521] truncate">
                          {lang === 'ar' ? asg.titleAr : asg.title}
                        </p>
                        <p className="text-[11px] text-[#6E645D] tabular-nums">
                          {t('Assignment', 'تكليف')} · {(asg.questions || []).length} {t('Q', 'س')} · {pts} {t('pts', 'د')}
                          {asg.grade != null ? ` · ${asg.grade}%` : ''}
                        </p>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <StatusBadge status={asg.status} />
                        <button
                          type="button"
                          onClick={() => {
                            setCourseTab('Assignments');
                            setActiveAsgId(asg.id);
                          }}
                          className="rounded-lg bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-1 text-[11px] font-bold text-[#960D03]"
                        >
                          {t('Open', 'فتح')}
                        </button>
                      </div>
                    </div>
                  );
                })}
                {courseQuizzes.map((qz) => {
                  const pts = (qz.questions || []).reduce((sum, q) => sum + (q.points || 0), 0);
                  return (
                    <div
                      key={qz.id}
                      className="flex items-center justify-between gap-2 rounded-xl border border-[#E8E3D9] bg-white px-3.5 py-2.5"
                    >
                      <div className="min-w-0">
                        <p className="text-xs font-bold text-[#302521] truncate">
                          {lang === 'ar' ? qz.titleAr : qz.title}
                        </p>
                        <p className="text-[11px] text-[#6E645D] tabular-nums">
                          {qz.kind} · {qz.duration} {t('min', 'د')} · {pts > 0 ? `${pts} ${t('pts', 'د')}` : qz.date}
                        </p>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <StatusBadge status={qz.status} />
                        <button
                          type="button"
                          onClick={() => {
                            setCourseTab('Quizzes & Exams');
                            if (qz.questions?.length) setActiveQuizId(qz.id);
                          }}
                          className="rounded-lg bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-1 text-[11px] font-bold text-[#960D03]"
                        >
                          {t('Open', 'فتح')}
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {courseGrades.length ? (
              <div className="space-y-2.5">
                {courseGrades.map((row) => (
                  <div
                    key={row.id}
                    className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4"
                  >
                    <div className="space-y-1 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm font-bold text-[#302521]">{row.student}</span>
                        <StatusBadge status={row.status} />
                      </div>
                      <p className="text-xs font-semibold text-[#302521]">{row.assessment}</p>
                      <p className="text-xs text-[#6E645D]">{row.feedback}</p>
                    </div>
                    <div className="flex items-center gap-2.5 shrink-0">
                      {isStaff ? (
                        <>
                          <input
                            type="number"
                            min="0"
                            max="100"
                            aria-label={t(`Score for ${row.student}`, `درجة ${row.student}`)}
                            value={row.score}
                            onChange={(e) =>
                              handleUpdateCourseGradeRow(row.id, {
                                score: Math.min(100, Math.max(0, Number(e.target.value) || 0)),
                              })
                            }
                            className="w-20 rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-1.5 text-center text-xs font-extrabold tabular-nums"
                          />
                          <select
                            aria-label={t(`Status for ${row.student}`, `حالة ${row.student}`)}
                            value={row.status}
                            onChange={(e) => {
                              handleUpdateCourseGradeRow(row.id, { status: e.target.value });
                              showToast(t(`Grade updated to ${e.target.value}.`, `تم تحديث الدرجة إلى ${e.target.value}.`));
                            }}
                            className="rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-1.5 text-xs font-bold"
                          >
                            <option value="Draft">Draft</option>
                            <option value="Needs review">Needs review</option>
                            <option value="Approved">Approved</option>
                            <option value="Published">Published</option>
                          </select>
                        </>
                      ) : (
                        <span className="rounded-xl bg-white border border-[#E8E3D9] px-3 py-1.5 text-sm font-extrabold text-[#B81104] tabular-nums">
                          {row.score}/100
                        </span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 text-xs text-[#6E645D]">
                {t('Overall standing calculated from quizzes & coursework:', 'التقييم محسوب من الاختبارات وأعمال السنة:')}{' '}
                <strong className="text-[#302521] tabular-nums">{course.grade}/100</strong>.
              </p>
            )}

            {!isStaff ? (
              <form
                onSubmit={handleStudentCourseAppeal}
                className="rounded-xl border border-dashed border-[#B81104]/30 bg-[#FCFBF6] p-4 space-y-3"
              >
                <h3 className="text-xs font-extrabold text-[#302521]">
                  {t(`Request Grade Review in ${course.id}`, `تقديم التماس مراجعة درجة في ${course.id}`)}
                </h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                  <input
                    type="text"
                    value={appealTarget}
                    onChange={(e) => setAppealTarget(e.target.value)}
                    placeholder={t('Assessment (e.g., Midterm / Quiz 1)', 'اسم التقييم')}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                  />
                  <input
                    type="text"
                    value={appealNote}
                    onChange={(e) => setAppealNote(e.target.value)}
                    placeholder={t('Question number & review explanation...', 'رقم السؤال وسبب طلب المراجعة...')}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                  />
                </div>
                <button
                  type="submit"
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-[#FFFACD]"
                >
                  <Send className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('Submit Appeal', 'إرسال الالتماس')}</span>
                </button>
              </form>
            ) : null}
          </div>
        ) : courseTab === 'Attendance' ? (
          <div className="space-y-5">
            {isStaff ? (
              <>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h2 className="text-lg font-bold text-[#302521]">
                      {t(`Section Attendance Roster · ${course.id}`, `سجل حضور الطلاب · ${course.id}`)}
                    </h2>
                    <p className="text-xs text-[#6E645D]">
                      {t('Record lecture/lab/section presence for enrolled advisees and students.', 'تسجيل الحضور والغياب للمحاضرة أو المعمل أو السكشن.')}
                    </p>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <select
                      aria-label={t('Attendance session', 'جلسة الحضور')}
                      value={attendanceSession}
                      onChange={(e) => setAttendanceSession(e.target.value)}
                      className="rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs font-bold text-[#302521]"
                    >
                      <option value="Week 8 · Lecture">{t('Week 8 · Lecture', 'الأسبوع ٨ · محاضرة')}</option>
                      <option value="Week 8 · Lab">{t('Week 8 · Lab', 'الأسبوع ٨ · معمل')}</option>
                      <option value="Week 8 · Section">{t('Week 8 · Section', 'الأسبوع ٨ · سكشن')}</option>
                    </select>
                    <button
                      type="button"
                      onClick={handleMarkAllPresent}
                      className="rounded-xl border border-[#16845B]/35 bg-[#E8F5EC] px-3.5 py-2 text-xs font-bold text-[#16845B] hover:bg-[#D5EFE0]"
                    >
                      {t('Mark All Present', 'تحضير الجميع')}
                    </button>
                    <button
                      type="button"
                      onClick={() =>
                        showToast(
                          t(
                            `Saved ${course.id} (${attendanceSession}) roster.`,
                            `تم حفظ سجل حضور ${course.id} (${attendanceSession}).`
                          )
                        )
                      }
                      className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-[#FFFACD]"
                    >
                      <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                      <span>{t('Save Session Attendance', 'حفظ سجل الحضور')}</span>
                    </button>
                  </div>
                </div>

                <div className="divide-y divide-[#E8E3D9] rounded-xl border border-[#E8E3D9] bg-white">
                  {studentRoster.map((st) => {
                    const currentVal = courseAttendanceMap[st.id] || 'Present';
                    const badge = attendanceBadgeProps(currentVal, t);
                    return (
                      <div
                        key={st.id}
                        className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3.5"
                      >
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-bold text-[#302521]">
                              {lang === 'ar' ? st.nameAr : st.name}
                            </span>
                            <StatusBadge status={badge.status} label={badge.label} />
                          </div>
                          <p className="text-xs text-[#6E645D] tabular-nums">
                            {st.subRole} · {t('Term Attendance:', 'نسبة الحضور:')} {st.attendance}%
                          </p>
                        </div>
                        <div className="flex flex-wrap gap-1.5">
                          {ATTENDANCE_OPTIONS.map((opt) => (
                            <button
                              key={opt}
                              type="button"
                              onClick={() => handleRosterStatusChange(st.id, opt)}
                              className={`rounded-lg border px-2.5 py-1 text-xs font-bold transition ${
                                currentVal === opt
                                  ? 'border-[#B81104] bg-[#B81104] text-[#FFFACD]'
                                  : 'border-[#E8E3D9] bg-[#FCFBF6] text-[#6E645D] hover:border-[#B81104]/40'
                              }`}
                            >
                              {opt}
                            </button>
                          ))}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </>
            ) : (
              <>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h2 className="text-lg font-bold text-[#302521]">
                      {t('Attendance Record & Policy Status', 'سجل الحضور وحالة الانتظام')}
                    </h2>
                    <p className="text-xs text-[#6E645D]">
                      {t('Minimum 85% attendance is required for final exam eligibility.', 'يشترط حضور ٨٥٪ على الأقل لدخول الامتحان النهائي.')}
                    </p>
                  </div>
                  <span className="rounded-xl bg-[#E8F5EC] px-3.5 py-2 text-sm font-extrabold text-[#16845B] tabular-nums">
                    {course.attendance}% {t('Present', 'نسبة الحضور')}
                  </span>
                </div>

                <div className="h-3 w-full rounded-full bg-[#EFECE5] overflow-hidden">
                  <div
                    className={`h-full rounded-full ${course.attendance >= 85 ? 'bg-[#16845B]' : 'bg-[#B76E00]'}`}
                    style={{ width: `${course.attendance}%` }}
                  />
                </div>

                <div className="space-y-2">
                  {[
                    { week: t('Week 8 · Lecture', 'الأسبوع ٨ · محاضرة'), date: '2026-11-15', room: 'Hall 101', state: 'Present' },
                    { week: t('Week 7 · Lab Session', 'الأسبوع ٧ · معمل'), date: '2026-11-09', room: 'Lab C-102', state: 'Present' },
                    { week: t('Week 6 · Tutorial Section', 'الأسبوع ٦ · سكشن'), date: '2026-11-05', room: 'Room S-202', state: 'Late' },
                    { week: t('Week 5 · Lecture', 'الأسبوع ٥ · محاضرة'), date: '2026-11-01', room: 'Hall 101', state: 'Present' },
                  ].map((log) => {
                    const badge = attendanceBadgeProps(log.state, t);
                    return (
                      <div
                        key={log.week}
                        className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5 text-xs"
                      >
                        <div>
                          <span className="font-bold text-[#302521]">{log.week}</span>
                          <p className="text-[#6E645D] tabular-nums">
                            {log.date} · {log.room} · {course.teacher}
                          </p>
                        </div>
                        <StatusBadge status={badge.status} label={badge.label} />
                      </div>
                    );
                  })}
                </div>
              </>
            )}
          </div>
        ) : courseTab === 'Announcements' ? (
          <div className="space-y-5">
            <h2 className="text-lg font-bold text-[#302521]">{t(`${course.id} Announcements`, `إعلانات ${course.id}`)}</h2>
            {isStaff ? (
              <form
                onSubmit={handlePostCourseAnnouncement}
                className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/35 p-4 space-y-2.5"
              >
                <input
                  type="text"
                  value={courseAnnTitle}
                  onChange={(e) => setCourseAnnTitle(e.target.value)}
                  placeholder={t(`Headline for ${course.id}...`, `عنوان إعلان ${course.id}...`)}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                />
                <textarea
                  rows={2}
                  value={courseAnnBody}
                  onChange={(e) => setCourseAnnBody(e.target.value)}
                  placeholder={t('Message for enrolled students and TAs...', 'نص الإعلان للطلاب والمعيدين...')}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                />
                <button
                  type="submit"
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-[#FFFACD]"
                >
                  <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('Post to Course', 'نشر للمقرر')}</span>
                </button>
              </form>
            ) : null}

            <div className="space-y-3">
              {courseAnnouncements.map((ann) => (
                <div key={ann.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-1">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h3 className="text-sm font-bold text-[#302521]">{lang === 'ar' ? ann.titleAr : ann.title}</h3>
                    <span className="text-[11px] text-[#6E645D] tabular-nums">{ann.date}</span>
                  </div>
                  <p className="text-xs text-[#6E645D]">{ann.body}</p>
                </div>
              ))}
            </div>
          </div>
        ) : (
          /* Discussion Tab */
          <div className="space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h2 className="text-lg font-bold text-[#302521]">
                  {t(`${course.id} Course Group Discussion`, `مناقشة مقرر ${course.id}`)}
                </h2>
                <p className="text-xs text-[#6E645D]">
                  {t('Synced directly with your Cohort Chats workspace.', 'متزامن مباشرة مع نظام المحادثات في المنصة.')}
                </p>
              </div>
              <button
                type="button"
                onClick={() => navigate('messages', { chatThread: threadId })}
                className="inline-flex items-center gap-1.5 rounded-xl border border-[#E8E3D9] bg-white px-3 py-1.5 text-xs font-bold text-[#B81104] hover:border-[#B81104]"
              >
                <span>{t('Open Full Chats View', 'فتح شاشة المحادثات الكاملة')}</span>
                <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
              </button>
            </div>

            <div className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 space-y-3 max-h-[320px] overflow-y-auto">
              {discussionMessages.map((m) => {
                const isMine = m.senderId ? m.senderId === profile.id : m.senderRole === role;
                return (
                  <div key={m.id} className={`flex ${isMine ? 'justify-end' : 'justify-start'}`}>
                    <div
                      className={`max-w-lg rounded-2xl px-4 py-2.5 text-xs sm:text-sm space-y-1 ${
                        isMine
                          ? 'bg-[#B81104] text-[#FFFACD]'
                          : 'bg-white border border-[#E5DCCF] text-[#1A1715]'
                      }`}
                    >
                      <div className="flex items-center justify-between gap-4 text-[11px] opacity-85 font-bold">
                        <span>
                          {m.sender} · {m.senderRole}
                        </span>
                        <span className="tabular-nums">{m.time}</span>
                      </div>
                      <p>{m.text}</p>
                    </div>
                  </div>
                );
              })}
            </div>

            <form onSubmit={handleSendDiscussion} className="flex gap-2">
              <input
                type="text"
                value={chatDraft}
                onChange={(e) => setChatDraft(e.target.value)}
                aria-label={t(`Post message in ${course.id}`, `اكتب رسالة في ${course.id}`)}
                placeholder={t(`Post to ${course.id} group discussion...`, `اكتب مشاركتك في مناقشة ${course.id}...`)}
                className="flex-1 rounded-xl border border-[#D6CFC1] bg-white px-4 py-2.5 text-xs sm:text-sm text-[#302521]"
              />
              <button
                type="submit"
                className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2.5 text-xs sm:text-sm font-bold text-[#FFFACD] hover:bg-[#940E03]"
              >
                <Send className="h-4 w-4" aria-hidden="true" />
                <span>{t('Post', 'إرسال')}</span>
              </button>
            </form>
          </div>
        )}
      </div>
    </section>
  );
}
