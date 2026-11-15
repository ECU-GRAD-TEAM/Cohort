import React, { useMemo, useState } from 'react';
import {
  ArrowUpRight,
  BarChart3,
  Bell,
  BookOpen,
  Calendar,
  CalendarPlus,
  CheckCircle2,
  ClipboardCheck,
  Clock,
  FileCheck2,
  MapPin,
  Megaphone,
  Plus,
  Sparkles,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { StatusBadge } from '../common/StatusBadge';

const STAFF_APPOINTMENT_TARGETS = [
  { name: 'Dr. Leila Hassan', roleLabel: 'Academic Advisor', location: 'Eng Bldg · Room B-201' },
  { name: 'Dr. Michael Tan', roleLabel: 'CS201 Lecturer', location: 'Eng Bldg · Room B-214' },
  { name: 'Dr. Sarah Kim', roleLabel: 'CS305 Lecturer', location: 'Eng Bldg · Room B-219' },
  { name: 'Eng. Kareem Adel', roleLabel: 'CS201 Teaching Assistant', location: 'TA Wing · Room C-108' },
];

export function DashboardPage() {
  const { role, lang, t, profile, data, setData, navigate, showToast } = useCohort();
  const isStaff = role === 'Academic Staff';
  const firstName = (lang === 'ar' && profile.nameAr ? profile.nameAr : profile.name).split(' ')[0];

  const [calendarFilter, setCalendarFilter] = useState('All');
  const [bookingOpen, setBookingOpen] = useState(false);
  const [aptStaff, setAptStaff] = useState(STAFF_APPOINTMENT_TARGETS[0].name);
  const [aptSlot, setAptSlot] = useState('Wed Nov 18 · 11:30–11:50');
  const [aptTopic, setAptTopic] = useState('');

  const [annOpen, setAnnOpen] = useState(false);
  const [annTitle, setAnnTitle] = useState('');
  const [annCourse, setAnnCourse] = useState('All');
  const [annBody, setAnnBody] = useState('');

  const upcomingAssignments = useMemo(
    () => data.assignments.filter((a) => !a.submitted),
    [data.assignments]
  );
  const pendingGrades = useMemo(
    () => data.gradeReviews.filter((g) => g.status !== 'Published'),
    [data.gradeReviews]
  );

  const calendarEvents = useMemo(() => {
    const baseEvents = [
      {
        id: 'cal-reg',
        date: '2026-11-15',
        dateLabel: t('Nov 15', '١٥ نوفمبر'),
        category: 'Milestones',
        status: 'Open',
        title: t(
          'Fall Add/Drop & 7-Course Registration Window',
          'نافذة تعديل وتسجيل المقررات (حتى ٧ مقررات)'
        ),
        meta: t('Registrar Portal · 09:00–16:00', 'بوابة التسجيل · ٠٩:٠٠–١٦:٠٠'),
        targetPage: 'registration',
      },
      ...data.quizzes.map((q) => ({
        id: `cal-${q.id}`,
        date: q.date.slice(0, 10),
        dateLabel: q.date.slice(5, 10),
        category: 'Exams & Quizzes',
        status: q.status,
        title: `${q.course} · ${lang === 'ar' ? q.titleAr : q.title}`,
        meta: `${q.kind} · ${q.duration} ${t('min', 'دقيقة')}${q.room ? ` · ${q.room}` : ''}`,
        targetPage: 'courses',
        targetOptions: { courseId: q.course, courseTab: 'Quizzes & Exams' },
      })),
      ...data.assignments.map((a) => ({
        id: `cal-${a.id}`,
        date: a.due.slice(0, 10),
        dateLabel: a.due.slice(5, 10),
        category: 'Assignments',
        status: a.status,
        title: `${a.course} · ${lang === 'ar' ? a.titleAr : a.title}`,
        meta: `${t('Due', 'التسليم')} ${a.due} · ${a.templateType}`,
        targetPage: 'courses',
        targetOptions: { courseId: a.course, courseTab: 'Assignments' },
      })),
      ...data.appointments.map((apt, idx) => ({
        id: `cal-${apt.id}`,
        date: `2026-11-${17 + (idx % 4)}`,
        dateLabel: apt.slot.split(' · ')[0] || 'Nov 17',
        category: 'Appointments',
        status: apt.status,
        title: isStaff
          ? `${apt.studentName} · ${apt.topic}`
          : `${apt.withName} · ${apt.topic}`,
        meta: `${apt.slot} · ${apt.location}`,
        targetPage: 'schedule',
      })),
    ].sort((a, b) => a.date.localeCompare(b.date));

    if (calendarFilter === 'All') return baseEvents;
    return baseEvents.filter((ev) => ev.category === calendarFilter);
  }, [calendarFilter, data.appointments, data.assignments, data.quizzes, isStaff, lang, t]);

  const avgClassScore = useMemo(() => {
    if (!data.courses.length) return 0;
    const sum = data.courses.reduce((acc, c) => acc + c.grade, 0);
    return Math.round(sum / data.courses.length);
  }, [data.courses]);

  const handleBookAppointment = (e) => {
    e.preventDefault();
    if (!aptTopic.trim()) {
      showToast(t('Enter an appointment topic first.', 'أدخل موضوع الموعد أولاً.'));
      return;
    }
    const target =
      STAFF_APPOINTMENT_TARGETS.find((s) => s.name === aptStaff) || STAFF_APPOINTMENT_TARGETS[0];
    const newApt = {
      id: `apt-${Date.now()}`,
      withName: target.name,
      roleLabel: target.roleLabel,
      studentName: profile.name,
      slot: aptSlot,
      location: target.location,
      topic: aptTopic.trim(),
      status: 'Pending',
    };
    setData((prev) => ({
      ...prev,
      appointments: [newApt, ...prev.appointments],
    }));
    setAptTopic('');
    setBookingOpen(false);
    showToast(
      t(
        `Appointment requested with ${target.name} (${aptSlot}).`,
        `تم إرسال طلب موعد مع ${target.name}.`
      )
    );
  };

  const updateAppointmentStatus = (id, status) => {
    setData((prev) => ({
      ...prev,
      appointments: prev.appointments.map((apt) =>
        apt.id === id ? { ...apt, status } : apt
      ),
    }));
    showToast(t(`Appointment marked ${status}.`, `تم تحديث الموعد إلى ${status}.`));
  };

  const handlePostAnnouncement = (e) => {
    e.preventDefault();
    if (!annTitle.trim() || !annBody.trim()) {
      showToast(t('Enter an announcement title and message.', 'أدخل عنوان الإعلان ونصه.'));
      return;
    }
    const newAnn = {
      id: `ann-${Date.now()}`,
      title: annTitle.trim(),
      titleAr: annTitle.trim(),
      audience: annCourse,
      course: annCourse === 'All' ? 'Academic Staff Notice' : annCourse,
      date: new Date().toISOString().slice(0, 10),
      body: annBody.trim(),
    };
    setData((prev) => ({
      ...prev,
      announcements: [newAnn, ...prev.announcements],
    }));
    setAnnTitle('');
    setAnnBody('');
    setAnnOpen(false);
    showToast(t('Announcement published to course feeds.', 'تم نشر الإعلان بنجاح.'));
  };

  return (
    <section className="page-enter space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {isStaff
              ? t('COHORT / ACADEMIC STAFF WORKSPACE', 'COHORT / مساحة هيئة التدريس')
              : t('COHORT / STUDENT WORKSPACE', 'COHORT / مساحة الطالب')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {isStaff
              ? t(`Welcome back, ${firstName}`, `مرحبًا بعودتك، ${firstName}`)
              : t(`Good day, ${firstName}`, `مرحبًا، ${firstName}`)}
          </h1>
          <p className="mt-1 text-sm text-[#6E645D]">
            {isStaff
              ? t(
                  'Your courses, grading queue, advisees, and teaching schedule in one place.',
                  'مقرراتك وقائمة المراجعة وطلاب الإرشاد وجدول التدريس في مكان واحد.'
                )
              : t(
                  'Assignments, quizzes, exams, schedule, and academic progress at a glance.',
                  'التكليفات والاختبارات والامتحانات والجدول والتقدم الأكاديمي في مكان واحد.'
                )}
          </p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-xl border border-[#E8E3D9] bg-white px-3.5 py-2 text-xs font-semibold text-[#302521]">
          <Calendar className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
          <span>{t('Week 8 · Fall Semester 2026', 'الأسبوع ٨ · فصل خريف ٢٠٢٦')}</span>
        </div>
      </div>

      {/* Hero Callout (Red Panel) */}
      <div className="cohort-hero rounded-2xl p-6 sm:p-8 flex flex-col justify-between gap-6 md:flex-row md:items-center">
        <div className="space-y-3 max-w-xl">
          <span className="inline-block rounded-md bg-white/15 px-2.5 py-1 text-[10px] font-bold tracking-widest uppercase text-[#FFFACD]">
            {isStaff
              ? t('FACULTY WORKSPACE · FALL 2026', 'مساحة هيئة التدريس · خريف ٢٠٢٦')
              : t('STUDENT WORKSPACE · FALL 2026', 'مساحة الطالب · خريف ٢٠٢٦')}
          </span>
          <h2 className="text-2xl font-bold leading-snug sm:text-3xl">
            {isStaff
              ? t('Stay ahead of reviews, classes, and advisees.', 'تابع المراجعات والمحاضرات وطلابك بسهولة.')
              : t('Small steps today. Big possibilities tomorrow.', 'خطوات بسيطة اليوم تصنع فارقًا كبيرًا غدًا.')}
          </h2>
          <p className="text-xs leading-relaxed text-[#FFFACD]/90 sm:text-sm">
            {isStaff
              ? t(
                  `You have ${pendingGrades.length} grade reviews pending and ${data.petitions.length} advisee petitions.`,
                  `لديك ${pendingGrades.length} مراجعة درجات معلّقة و ${data.petitions.length} التماس إرشاد أكاديمي.`
                )
              : t(
                  `You have ${upcomingAssignments.length} upcoming assignments and ${data.quizzes.length} active quizzes & exams.`,
                  `لديك ${upcomingAssignments.length} تكليفات قادمة و ${data.quizzes.length} اختبارات وامتحانات نشطة.`
                )}
          </p>
          <div className="flex flex-wrap gap-2.5 pt-1">
            <button
              type="button"
              onClick={() => navigate(isStaff ? 'grading' : 'schedule')}
              className="inline-flex min-h-[42px] items-center gap-2 rounded-xl bg-[#FFFACD] px-4 py-2 text-xs font-bold text-[#B81104] transition hover:bg-[#FFF2B5]"
            >
              <span>
                {isStaff
                  ? t('Open Grading & Builder', 'فتح التقييم والبناء')
                  : t('View Schedule Table', 'عرض جدول المحاضرات')}
              </span>
              <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
            </button>
            <button
              type="button"
              onClick={() => navigate('courses')}
              className="inline-flex min-h-[42px] items-center gap-2 rounded-xl border border-[#FFFACD]/50 px-4 py-2 text-xs font-bold text-[#FFFACD] transition hover:bg-white/10"
            >
              <BookOpen className="h-4 w-4" aria-hidden="true" />
              <span>{t('Open Courses Workspace', 'فتح مساحة المقررات')}</span>
            </button>
          </div>
        </div>

        {/* Role-specific Quick Actions */}
        <div className="rounded-2xl border border-[#FFFACD]/25 bg-white/10 p-4 text-xs space-y-2 md:min-w-[270px]">
          <p className="font-bold text-[#FFFACD] uppercase tracking-wider text-[10px]">
            {t('Quick Actions', 'إجراءات سريعة')}
          </p>
          {isStaff ? (
            <>
              <button
                type="button"
                onClick={() => navigate('registration')}
                className="flex w-full items-center justify-between rounded-xl bg-white/10 px-3 py-2 text-start font-semibold text-white hover:bg-white/20"
              >
                <span>{t('Advisee Course Approvals', 'اعتماد تسجيل المقررات')}</span>
                <ClipboardCheck className="h-4 w-4 text-[#FFFACD]" aria-hidden="true" />
              </button>
              <button
                type="button"
                onClick={() => navigate('grading')}
                className="flex w-full items-center justify-between rounded-xl bg-white/10 px-3 py-2 text-start font-semibold text-white hover:bg-white/20"
              >
                <span>{t('Grading & Template Studio', 'استوديو التقييم والقوالب')}</span>
                <FileCheck2 className="h-4 w-4 text-[#FFFACD]" aria-hidden="true" />
              </button>
              <button
                type="button"
                onClick={() => navigate('assistant')}
                className="flex w-full items-center justify-between rounded-xl bg-white/10 px-3 py-2 text-start font-semibold text-white hover:bg-white/20"
              >
                <span>{t('Open AI Assistant', 'فتح المساعد الذكي')}</span>
                <Sparkles className="h-4 w-4 text-[#FFFACD]" aria-hidden="true" />
              </button>
            </>
          ) : (
            <>
              <button
                type="button"
                onClick={() => navigate('courses', { courseTab: 'Assignments' })}
                className="flex w-full items-center justify-between rounded-xl bg-white/10 px-3 py-2 text-start font-semibold text-white hover:bg-white/20"
              >
                <span>{t('Upcoming Assignments', 'التكليفات والمواعيد القادمة')}</span>
                <FileCheck2 className="h-4 w-4 text-[#FFFACD]" aria-hidden="true" />
              </button>
              <button
                type="button"
                onClick={() => navigate('assistant')}
                className="flex w-full items-center justify-between rounded-xl bg-white/10 px-3 py-2 text-start font-semibold text-white hover:bg-white/20"
              >
                <span>{t('Open AI Assistant', 'فتح المساعد الذكي')}</span>
                <Sparkles className="h-4 w-4 text-[#FFFACD]" aria-hidden="true" />
              </button>
              <button
                type="button"
                onClick={() => navigate('map')}
                className="flex w-full items-center justify-between rounded-xl bg-white/10 px-3 py-2 text-start font-semibold text-white hover:bg-white/20"
              >
                <span>{t('Campus Map & Labs', 'خريطة الجامعة والمعامل')}</span>
                <MapPin className="h-4 w-4 text-[#FFFACD]" aria-hidden="true" />
              </button>
            </>
          )}
        </div>
      </div>

      {/* 4 KPI Summary Cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <button
          type="button"
          onClick={() => navigate('academic-affairs')}
          className="cohort-card p-5 text-start transition hover:border-[#B81104]/50"
        >
          <span className="text-xs font-semibold text-[#6E645D]">
            {isStaff ? t('Enrolled Students', 'الطلاب المسجلون') : t('Cumulative GPA', 'المعدل التراكمي')}
          </span>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">
            {isStaff ? '128' : '3.82'}
          </p>
          <span className="mt-1 block text-xs font-semibold text-[#16845B]">
            {isStaff ? t('View cohort analytics →', 'تحليلات الدفعة ←') : t('Dean’s List Standing →', 'قائمة التميز ←')}
          </span>
        </button>

        <button
          type="button"
          onClick={() => navigate('courses')}
          className="cohort-card p-5 text-start transition hover:border-[#B81104]/50"
        >
          <span className="text-xs font-semibold text-[#6E645D]">
            {t('Active Courses', 'المقررات النشطة')}
          </span>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">
            {data.courses.length}
          </p>
          <span className="mt-1 block text-xs text-[#6E645D]">
            {t('8-tab interactive workspaces', 'مساحات مقررات من ٨ تبويبات')}
          </span>
        </button>

        <button
          type="button"
          onClick={() => navigate(isStaff ? 'grading' : 'courses', { courseTab: 'Assignments' })}
          className="cohort-card p-5 text-start transition hover:border-[#B81104]/50"
        >
          <span className="text-xs font-semibold text-[#6E645D]">
            {isStaff ? t('Pending Grade Reviews', 'مراجعات الدرجات') : t('Upcoming Assignments', 'التكليفات القادمة')}
          </span>
          <p className="mt-2 text-3xl font-extrabold text-[#B81104] tabular-nums">
            {isStaff ? pendingGrades.length : upcomingAssignments.length}
          </p>
          <span className="mt-1 block text-xs text-[#6E645D]">
            {isStaff ? t('Drafts & appeals', 'مسودات والتماسات') : t('Due this week', 'مستحقة هذا الأسبوع')}
          </span>
        </button>

        <button
          type="button"
          onClick={() => navigate('schedule')}
          className="cohort-card p-5 text-start transition hover:border-[#B81104]/50"
        >
          <span className="text-xs font-semibold text-[#6E645D]">
            {isStaff
              ? t('Scheduled Duties & Classes', 'الواجبات والمحاضرات المجدولة')
              : t('Scheduled Sessions', 'الجلسات المجدولة')}
          </span>
          <p className="mt-2 text-3xl font-extrabold text-[#302521] tabular-nums">
            {
              data.schedule.filter((s) =>
                isStaff ? s.forStaff || s.lecturer === profile.name : s.forStudent !== false
              ).length
            }
          </p>
          <span className="mt-1 block text-xs text-[#6E645D]">
            {isStaff
              ? t('Your classes, labs & office hours', 'محاضراتك وساعاتك المكتبية')
              : t('Lectures, Labs & Sections', 'محاضرات ومعامل وسكاشن')}
          </span>
        </button>
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        {/* Left Column (8 cols) */}
        <div className="space-y-6 lg:col-span-8">
          {/* Courses Strip */}
          <div className="cohort-card p-6">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-base font-bold text-[#302521]">
                {isStaff ? t('Courses Taught & Coordinated', 'المقررات المُدرَّسة والمنسقة') : t('My Courses', 'مقرراتي')}
              </h2>
              <button
                type="button"
                onClick={() => navigate('courses')}
                className="text-xs font-bold text-[#B81104] hover:underline"
              >
                {t('All courses →', 'كل المقررات ←')}
              </button>
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              {data.courses.slice(0, 3).map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => navigate('courses', { courseId: c.id, courseTab: 'Overview' })}
                  className="overflow-hidden rounded-xl border border-[#E8E3D9] bg-white text-start transition hover:-translate-y-0.5 hover:border-[#B81104]/60"
                >
                  <div
                    className="flex h-20 items-start justify-between p-3"
                    style={{ backgroundColor: c.accent }}
                  >
                    <span className="rounded bg-white/80 px-2 py-0.5 text-[10px] font-bold text-[#302521]">
                      {c.id}
                    </span>
                    <span className="font-mono text-2xl font-bold text-[#B81104]">{c.symbol}</span>
                  </div>
                  <div className="p-3.5">
                    <h3 className="truncate text-sm font-bold text-[#302521]">
                      {lang === 'ar' ? c.nameAr : c.name}
                    </h3>
                    <p className="mt-0.5 truncate text-xs text-[#6E645D]">{c.teacher}</p>
                    <div className="mt-3 flex items-center justify-between text-[11px] font-semibold text-[#6E645D]">
                      <span>{t('Progress', 'التقدم')}</span>
                      <span className="tabular-nums text-[#B81104]">{c.progress}%</span>
                    </div>
                    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-[#EFECE5]">
                      <div className="h-full rounded-full bg-[#B81104]" style={{ width: `${c.progress}%` }} />
                    </div>
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* Interactive Academic Calendar & Deadlines Strip */}
          <div className="cohort-card p-6 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <Calendar className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
                <h2 className="text-base font-bold text-[#302521]">
                  {t('Academic Calendar & Deadlines', 'التقويم الأكاديمي والمواعيد')}
                </h2>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {[
                  { id: 'All', label: t('All', 'الكل') },
                  { id: 'Exams & Quizzes', label: t('Exams & Quizzes', 'اختبارات وامتحانات') },
                  { id: 'Assignments', label: t('Assignments', 'التكليفات') },
                  { id: 'Appointments', label: t('Appointments', 'المواعيد') },
                ].map((pill) => (
                  <button
                    key={pill.id}
                    type="button"
                    onClick={() => setCalendarFilter(pill.id)}
                    className={`rounded-full border px-3 py-1 text-[11px] font-bold transition ${
                      calendarFilter === pill.id
                        ? 'border-[#B81104] bg-[#B81104] text-[#FFFACD]'
                        : 'border-[#E8E3D9] bg-[#FCFBF6] text-[#6E645D] hover:border-[#B81104]/40'
                    }`}
                  >
                    {pill.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-2.5">
              {calendarEvents.map((ev) => (
                <div
                  key={ev.id}
                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5"
                >
                  <div className="flex items-start gap-3">
                    <div className="rounded-xl bg-[#FFFACD] border border-[#E9DBA9] px-3 py-1.5 text-center shrink-0">
                      <div className="text-[11px] font-extrabold text-[#B81104] tabular-nums">
                        {ev.dateLabel}
                      </div>
                    </div>
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <h3 className="text-xs sm:text-sm font-bold text-[#302521]">{ev.title}</h3>
                        <StatusBadge status={ev.status} />
                      </div>
                      <p className="text-[11px] text-[#6E645D] mt-0.5">{ev.meta}</p>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => navigate(ev.targetPage, ev.targetOptions)}
                    className="self-start sm:self-center shrink-0 rounded-lg border border-[#E8E3D9] bg-white px-3 py-1.5 text-[11px] font-bold text-[#B81104] hover:border-[#B81104]"
                  >
                    {t('Open →', 'فتح ←')}
                  </button>
                </div>
              ))}
            </div>
          </div>

          {/* Analytical Overview Section */}
          <div className="cohort-card p-6 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                <BarChart3 className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
                <div>
                  <h2 className="text-base font-bold text-[#302521]">
                    {isStaff
                      ? t('Section Performance & Grading Overview', 'ملخص أداء الشُعب وحالة التصحيح')
                      : t('Analytical Overview · Grades & Attendance', 'نظرة تحليلية · الدرجات والحضور')}
                  </h2>
                  <p className="text-xs text-[#6E645D]">
                    {isStaff
                      ? t(
                          `Average section mastery ${avgClassScore}% · ${pendingGrades.length} pending review(s)`,
                          `متوسط إتقان الشُعب ${avgClassScore}٪ · ${pendingGrades.length} درجات قيد المراجعة`
                        )
                      : t(
                          'Course score progression against the 85% attendance policy minimum.',
                          'مؤشر الدرجات ونسبة الحضور مقارنة بحد السياسة الأكاديمية ٨٥٪.'
                        )}
                  </p>
                </div>
              </div>
              {isStaff ? (
                <button
                  type="button"
                  onClick={() => navigate('grading')}
                  className="rounded-xl bg-[#B81104] px-3.5 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
                >
                  {t('Open Grading Studio', 'فتح استوديو التقييم')}
                </button>
              ) : null}
            </div>

            <div className="space-y-3">
              {data.courses.map((c) => {
                const attendanceWatch = c.attendance < 88;
                return (
                  <div
                    key={c.id}
                    className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5 space-y-2"
                  >
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-xs font-bold text-[#302521]">
                        {c.id} · {lang === 'ar' ? c.nameAr : c.name}
                      </span>
                      <div className="flex flex-wrap items-center gap-2 text-xs tabular-nums">
                        <span className="font-extrabold text-[#B81104]">
                          {t('Grade:', 'الدرجة:')} {c.grade}%
                        </span>
                        {isStaff ? (
                          <span className="text-[#6E645D]">
                            {t('Capacity:', 'السعة:')} {c.enrolled}/{c.capacity}
                          </span>
                        ) : (
                          <span
                            className={`rounded-md px-2 py-0.5 text-[11px] font-bold ${
                              attendanceWatch
                                ? 'bg-[#FFF4D4] text-[#80540D]'
                                : 'bg-[#E8F5EC] text-[#16845B]'
                            }`}
                          >
                            {t('Attendance:', 'الحضور:')} {c.attendance}%
                          </span>
                        )}
                      </div>
                    </div>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                      <div>
                        <div className="flex justify-between text-[10px] font-semibold text-[#6E645D] mb-1">
                          <span>{isStaff ? t('Class Average', 'متوسط الشعبة') : t('Standing Grade', 'التحصيل')}</span>
                          <span className="tabular-nums">{c.grade}%</span>
                        </div>
                        <div className="h-2 w-full rounded-full bg-[#EFECE5] overflow-hidden">
                          <div className="h-full rounded-full bg-[#B81104]" style={{ width: `${c.grade}%` }} />
                        </div>
                      </div>
                      <div>
                        <div className="flex justify-between text-[10px] font-semibold text-[#6E645D] mb-1">
                          <span>{isStaff ? t('Seat Utilization', 'إشغال القاعة') : t('Attendance (min 85%)', 'الحضور (الحد الأدنى ٨٥٪)')}</span>
                          <span className="tabular-nums">
                            {isStaff ? `${Math.round((c.enrolled / c.capacity) * 100)}%` : `${c.attendance}%`}
                          </span>
                        </div>
                        <div className="h-2 w-full rounded-full bg-[#EFECE5] overflow-hidden">
                          <div
                            className={`h-full rounded-full ${
                              !isStaff && attendanceWatch ? 'bg-[#B76E00]' : 'bg-[#16845B]'
                            }`}
                            style={{
                              width: `${
                                isStaff ? Math.round((c.enrolled / c.capacity) * 100) : c.attendance
                              }%`,
                            }}
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Announcements with Staff Composer */}
          <div className="cohort-card p-6 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <Bell className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                <h2 className="text-base font-bold text-[#302521]">
                  {t('Announcements', 'الإعلانات')}
                </h2>
              </div>
              {isStaff ? (
                <button
                  type="button"
                  onClick={() => setAnnOpen((prev) => !prev)}
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[#FFFACD] border border-[#E9DBA9] px-3 py-1.5 text-xs font-bold text-[#B81104] hover:bg-[#FFF2B5]"
                >
                  <Megaphone className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{annOpen ? t('Cancel', 'إلغاء') : t('Post Announcement', 'نشر إعلان جديد')}</span>
                </button>
              ) : null}
            </div>

            {isStaff && annOpen ? (
              <form
                onSubmit={handlePostAnnouncement}
                className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/40 p-4 space-y-3"
              >
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
                  <input
                    type="text"
                    value={annTitle}
                    onChange={(e) => setAnnTitle(e.target.value)}
                    aria-label={t('Announcement title', 'عنوان الإعلان')}
                    placeholder={t('Announcement headline...', 'عنوان الإعلان...')}
                    className="sm:col-span-2 rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                  />
                  <select
                    aria-label={t('Target audience', 'الفئة المستهدفة')}
                    value={annCourse}
                    onChange={(e) => setAnnCourse(e.target.value)}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs font-semibold text-[#302521]"
                  >
                    <option value="All">{t('All Students', 'جميع الطلاب')}</option>
                    {data.courses.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.id}
                      </option>
                    ))}
                  </select>
                </div>
                <textarea
                  rows={2}
                  value={annBody}
                  onChange={(e) => setAnnBody(e.target.value)}
                  aria-label={t('Announcement message', 'نص الإعلان')}
                  placeholder={t('Share updates, deadlines, or lab notices...', 'أضف تفاصيل الإعلان أو تنبيهات المعمل...')}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                />
                <button
                  type="submit"
                  className="inline-flex items-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
                >
                  <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('Publish Announcement', 'نشر الإعلان')}</span>
                </button>
              </form>
            ) : null}

            <div className="divide-y divide-[#E8E3D9]">
              {data.announcements.map((ann) => (
                <div key={ann.id} className="py-3 first:pt-0 last:pb-0">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded bg-[#FFFACD] px-2 py-0.5 text-[10px] font-bold text-[#B81104]">
                        {ann.course}
                      </span>
                      <h3 className="text-sm font-bold text-[#302521]">
                        {lang === 'ar' ? ann.titleAr : ann.title}
                      </h3>
                    </div>
                    <span className="text-[11px] text-[#6E645D] tabular-nums">{ann.date}</span>
                  </div>
                  <p className="mt-1 text-xs text-[#6E645D]">{ann.body}</p>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Right Column (4 cols): Appointments & Quizzes/Exams */}
        <div className="space-y-6 lg:col-span-4">
          <div className="cohort-card p-6 space-y-4">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <Clock className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                <h2 className="text-base font-bold text-[#302521]">
                  {t('Appointments', 'المواعيد')}
                </h2>
              </div>
              {!isStaff ? (
                <button
                  type="button"
                  onClick={() => setBookingOpen((prev) => !prev)}
                  className="inline-flex items-center gap-1 rounded-xl bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-1 text-[11px] font-bold text-[#B81104] hover:bg-[#FFF2B5]"
                >
                  <CalendarPlus className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{bookingOpen ? t('Close', 'إغلاق') : t('Book Slot', 'حجز موعد')}</span>
                </button>
              ) : null}
            </div>

            {!isStaff && bookingOpen ? (
              <form
                onSubmit={handleBookAppointment}
                className="rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/40 p-3.5 space-y-2.5"
              >
                <label htmlFor="apt-staff" className="block text-[11px] font-bold text-[#302521]">
                  {t('Advisor / Lecturer / TA', 'المرشد / المحاضر / المعيد')}
                </label>
                <select
                  id="apt-staff"
                  value={aptStaff}
                  onChange={(e) => setAptStaff(e.target.value)}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs text-[#302521]"
                >
                  {STAFF_APPOINTMENT_TARGETS.map((s) => (
                    <option key={s.name} value={s.name}>
                      {s.name} ({s.roleLabel})
                    </option>
                  ))}
                </select>
                <label htmlFor="apt-slot" className="block text-[11px] font-bold text-[#302521]">
                  {t('Preferred Slot', 'الموعد المناسب')}
                </label>
                <select
                  id="apt-slot"
                  value={aptSlot}
                  onChange={(e) => setAptSlot(e.target.value)}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs text-[#302521]"
                >
                  <option value="Wed Nov 18 · 11:30–11:50">Wed Nov 18 · 11:30–11:50</option>
                  <option value="Thu Nov 19 · 14:00–14:20">Thu Nov 19 · 14:00–14:20</option>
                  <option value="Sun Nov 22 · 12:30–12:50">Sun Nov 22 · 12:30–12:50</option>
                </select>
                <input
                  type="text"
                  value={aptTopic}
                  onChange={(e) => setAptTopic(e.target.value)}
                  aria-label={t('Appointment topic', 'موضوع الموعد')}
                  placeholder={t('Topic (e.g., CS201 Lab check)...', 'موضوع الاستشارة...')}
                  className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs text-[#302521]"
                />
                <button
                  type="submit"
                  className="w-full rounded-xl bg-[#B81104] px-3 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
                >
                  {t('Confirm Booking Request', 'تأكيد طلب الموعد')}
                </button>
              </form>
            ) : null}

            <div className="space-y-3">
              {data.appointments.map((apt) => (
                <div key={apt.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3 space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-bold text-[#302521]">
                      {isStaff ? apt.studentName : apt.withName}
                    </span>
                    <StatusBadge status={apt.status} />
                  </div>
                  <p className="text-xs text-[#6E645D]">{apt.topic}</p>
                  <p className="text-[11px] font-semibold text-[#B81104]">
                    {apt.slot} · {apt.location}
                  </p>
                  {isStaff && apt.status !== 'Confirmed' ? (
                    <div className="flex flex-wrap gap-2 pt-1">
                      <button
                        type="button"
                        onClick={() => updateAppointmentStatus(apt.id, 'Confirmed')}
                        className="rounded-lg bg-[#16845B] px-2.5 py-1 text-[11px] font-bold text-white"
                      >
                        {t('Confirm', 'تأكيد')}
                      </button>
                      <button
                        type="button"
                        onClick={() => updateAppointmentStatus(apt.id, 'Completed')}
                        className="rounded-lg border border-[#E8E3D9] bg-white px-2.5 py-1 text-[11px] font-bold text-[#302521]"
                      >
                        {t('Complete', 'مكتمل')}
                      </button>
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
          </div>

          <div className="cohort-lemon-panel rounded-2xl p-6 space-y-3">
            <div className="flex items-center gap-2 text-[#B81104]">
              <BookOpen className="h-5 w-5" aria-hidden="true" />
              <h2 className="text-base font-bold">
                {t('Quizzes & Exams', 'الاختبارات والامتحانات')}
              </h2>
            </div>
            {data.quizzes.map((q) => (
              <div key={q.id} className="rounded-xl bg-white p-3.5 border border-[#E9DBA9]">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[11px] font-bold text-[#B81104]">{q.course} · {q.kind}</span>
                  <StatusBadge status={q.status} />
                </div>
                <p className="mt-1 text-xs font-bold text-[#302521]">
                  {lang === 'ar' ? q.titleAr : q.title}
                </p>
                <p className="mt-1 text-[11px] text-[#6E645D]">
                  {q.date} · {q.duration} {t('min', 'دقيقة')}
                </p>
              </div>
            ))}
            <button
              type="button"
              onClick={() => navigate('courses', { courseTab: 'Quizzes & Exams' })}
              className="flex w-full min-h-[40px] items-center justify-center gap-1.5 rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
            >
              <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
              <span>{t('Open Quizzes & Exams', 'فتح الاختبارات والامتحانات')}</span>
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
