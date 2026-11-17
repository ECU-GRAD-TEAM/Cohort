import React, { useMemo, useState } from 'react';
import {
  AlertCircle,
  CalendarDays,
  CalendarPlus,
  Clock,
  Download,
  LayoutGrid,
  Lock,
  MapPin,
  Plus,
  Printer,
  Table2,
  Trash2,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { CAMPUS_LOCATIONS } from '../../data/seedData';
import { validateRecord } from '../../utils/validation';
import { StatusBadge } from '../common/StatusBadge';

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu'];
const ALL_WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAY_DATE_MAP = {
  Sun: '2026-11-15',
  Mon: '2026-11-16',
  Tue: '2026-11-17',
  Wed: '2026-11-18',
  Thu: '2026-11-19',
};

function computeMinutesLabel(start, end) {
  const [sh, sm] = start.split(':').map(Number);
  const [eh, em] = end.split(':').map(Number);
  const diff = eh * 60 + em - (sh * 60 + sm);
  return diff > 0 ? `${diff} min` : '60 min';
}

function resolveAppointmentDate(apt) {
  if (apt.date) return apt.date.slice(0, 10);
  const match = String(apt.slot || '').match(/Nov\s+(\d{1,2})/i);
  if (match) {
    return `2026-11-${match[1].padStart(2, '0')}`;
  }
  return '2026-11-17';
}

const EVENT_TYPE_STYLES = {
  class: {
    dot: 'bg-[#B81104]',
    chip: 'bg-[#FFF0ED] text-[#960D03] border-[#B81104]/25',
  },
  assignment: {
    dot: 'bg-[#B76E00]',
    chip: 'bg-[#FFF4D4] text-[#80540D] border-[#B76E00]/25',
  },
  assessment: {
    dot: 'bg-[#16845B]',
    chip: 'bg-[#E8F5EC] text-[#16845B] border-[#16845B]/25',
  },
  appointment: {
    dot: 'bg-[#5D514A]',
    chip: 'bg-[#F3EFE6] text-[#302521] border-[#E8E3D9]',
  },
  personal: {
    dot: 'bg-[#7A0B02]',
    chip: 'bg-[#FFFACD] text-[#960D03] border-[#E9DBA9]',
  },
};

export function SchedulePage() {
  const { role, lang, t, profile, data, setData, navigate, showToast } = useCohort();
  const isStaff = role === 'Academic Staff';

  const [courseFilter, setCourseFilter] = useState('All');
  const [dayFilter, setDayFilter] = useState('All');
  const [typeFilter, setTypeFilter] = useState('All');
  const [viewMode, setViewMode] = useState('table');

  // Monthly calendar & student-only manual date state
  const [selectedDate, setSelectedDate] = useState('2026-11-17');
  const [personalDate, setPersonalDate] = useState('2026-11-18');
  const [personalTime, setPersonalTime] = useState('17:00');
  const [personalCategory, setPersonalCategory] = useState('Study Goal');
  const [personalTitle, setPersonalTitle] = useState('');

  // Staff add-session state
  const [addOpen, setAddOpen] = useState(false);
  const [newCourse, setNewCourse] = useState(data.courses[0]?.id || '');
  const [newType, setNewType] = useState('Office Hours');
  const [newDay, setNewDay] = useState('Wed');
  const [newStart, setNewStart] = useState('14:30');
  const [newEnd, setNewEnd] = useState('15:30');
  const [newLocation, setNewLocation] = useState('Room B-214');
  const [newBuildingId, setNewBuildingId] = useState('Engineering');
  const [formError, setFormError] = useState('');

  // Role-scoped schedule: Staff only sees his own teaching classes, lab supervision & advising duties
  const roleSchedule = useMemo(
    () =>
      data.schedule.filter((s) =>
        isStaff ? s.forStaff === true || s.lecturer === profile.name : s.forStudent !== false
      ),
    [data.schedule, isStaff, profile.name]
  );

  const availableTypes = useMemo(() => {
    const distinct = Array.from(new Set(roleSchedule.map((s) => s.type)));
    return ['All', ...distinct];
  }, [roleSchedule]);

  const rows = useMemo(
    () =>
      roleSchedule.filter((s) => {
        const cOk = courseFilter === 'All' || s.courseCode === courseFilter;
        const dOk = dayFilter === 'All' || s.day === dayFilter;
        const tOk = typeFilter === 'All' || s.type === typeFilter;
        return cOk && dOk && tOk;
      }),
    [courseFilter, dayFilter, roleSchedule, typeFilter]
  );

  // Build November 2026 Monthly Calendar Matrix & Events
  const novemberDays = useMemo(() => {
    const firstWeekday = new Date(2026, 10, 1).getDay(); // 0 = Sun
    const leadingBlanks = Array.from({ length: firstWeekday }, (_, i) => ({
      key: `blank-${i}`,
      empty: true,
    }));
    const days = Array.from({ length: 30 }, (_, idx) => {
      const dayNum = idx + 1;
      const iso = `2026-11-${String(dayNum).padStart(2, '0')}`;
      const weekday = ALL_WEEKDAYS[new Date(2026, 10, dayNum).getDay()];
      return { key: iso, empty: false, dayNum, iso, weekday };
    });
    return [...leadingBlanks, ...days];
  }, []);

  const eventsByDate = useMemo(() => {
    const map = {};
    const pushEvent = (iso, ev) => {
      if (!iso) return;
      if (!map[iso]) map[iso] = [];
      map[iso].push(ev);
    };

    // 1. Assignments
    data.assignments.forEach((a) => {
      pushEvent(a.due.slice(0, 10), {
        id: `cal-asg-${a.id}`,
        kind: 'assignment',
        badge: t('Assignment', 'تكليف'),
        title: `${a.course} · ${lang === 'ar' ? a.titleAr : a.title}`,
        meta: `${t('Due', 'التسليم')} ${a.due.slice(11) || '23:59'} · ${a.templateType}`,
        actionLabel: t('Open', 'فتح'),
        onAction: () => navigate('courses', { courseId: a.course, courseTab: 'Assignments' }),
      });
    });

    // 3. Quizzes & Exams
    data.quizzes.forEach((q) => {
      pushEvent(q.date.slice(0, 10), {
        id: `cal-qz-${q.id}`,
        kind: 'assessment',
        badge: q.kind,
        title: `${q.course} · ${lang === 'ar' ? q.titleAr : q.title}`,
        meta: `${q.duration} ${t('min', 'دقيقة')}${q.room ? ` · ${q.room}` : ''}`,
        actionLabel: t('Open', 'فتح'),
        onAction: () => navigate('courses', { courseId: q.course, courseTab: 'Quizzes & Exams' }),
      });
    });

    // 4. Appointments
    data.appointments.forEach((apt) => {
      pushEvent(resolveAppointmentDate(apt), {
        id: `cal-apt-${apt.id}`,
        kind: 'appointment',
        badge: t('Appointment', 'موعد'),
        title: isStaff ? `${apt.studentName} · ${apt.topic}` : `${apt.withName} · ${apt.topic}`,
        meta: `${apt.slot} · ${apt.location}`,
      });
    });

    // 5. Personal manual dates — strictly Student-only
    if (!isStaff) {
      (data.studentCalendarEvents || []).forEach((ev) => {
        pushEvent(ev.date, {
          id: ev.id,
          kind: 'personal',
          personalId: ev.id,
          badge: ev.category || t('Personal', 'شخصي'),
          title: ev.title,
          meta: `${ev.time || ''} · ${t('Only visible to you', 'مرئي لك فقط')}`,
        });
      });
    }

    return map;
  }, [
    data.appointments,
    data.assignments,
    data.quizzes,
    data.studentCalendarEvents,
    isStaff,
    lang,
    navigate,
    t,
  ]);

  const selectedDayEvents = eventsByDate[selectedDate] || [];

  const handleSelectCalendarDay = (iso) => {
    setSelectedDate(iso);
    setPersonalDate(iso);
  };

  const handleAddPersonalEvent = (e) => {
    e.preventDefault();
    if (isStaff) return;
    const cleanTitle = personalTitle.trim();
    if (!cleanTitle) {
      showToast(t('Enter a title for your personal calendar date.', 'أدخل عنواناً للموعد الشخصي.'));
      return;
    }
    const nextItem = {
      id: `stu-cal-${Date.now()}`,
      date: personalDate,
      title: cleanTitle,
      category: personalCategory,
      time: personalTime,
    };
    setData((prev) => ({
      ...prev,
      studentCalendarEvents: [...(prev.studentCalendarEvents || []), nextItem],
    }));
    setSelectedDate(personalDate);
    setPersonalTitle('');
    showToast(
      t(
        `Added "${cleanTitle}" on ${personalDate} (only visible to you).`,
        `تمت إضافة "${cleanTitle}" بتاريخ ${personalDate} (مرئي لك فقط).`
      )
    );
  };

  const handleDeletePersonalEvent = (personalId) => {
    setData((prev) => ({
      ...prev,
      studentCalendarEvents: (prev.studentCalendarEvents || []).filter(
        (ev) => ev.id !== personalId
      ),
    }));
    showToast(t('Removed personal calendar date.', 'تم حذف الموعد الشخصي.'));
  };

  const handlePrintSchedule = () => {
    if (typeof window !== 'undefined' && typeof window.print === 'function') {
      window.print();
    }
  };

  const handleExportICS = () => {
    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Cohort LMS//Weekly Timetable//EN',
      ...rows.flatMap((row) => {
        const ymd = (row.date || DAY_DATE_MAP[row.day] || '2026-11-15').replaceAll('-', '');
        const dtStart = `${ymd}T${row.start.replace(':', '')}00`;
        const dtEnd = `${ymd}T${row.end.replace(':', '')}00`;
        return [
          'BEGIN:VEVENT',
          `UID:${row.id}@cohort.edu`,
          `DTSTART:${dtStart}`,
          `DTEND:${dtEnd}`,
          `SUMMARY:${row.courseCode} ${row.type} - ${row.courseName}`,
          `LOCATION:${row.location}`,
          `DESCRIPTION:${row.lecturer}`,
          'END:VEVENT',
        ];
      }),
      'END:VCALENDAR',
    ];
    const blob = new Blob([lines.join('\r\n')], { type: 'text/calendar;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = isStaff ? 'cohort-staff-schedule.ics' : 'cohort-student-schedule.ics';
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    showToast(t('Exported schedule as iCalendar (.ics).', 'تم تصدير الجدول بصيغة iCalendar (.ics).'));
  };

  const handleAddSession = (e) => {
    e.preventDefault();
    const courseObj = data.courses.find((c) => c.id === newCourse);
    const mappedDate = DAY_DATE_MAP[newDay] || '2026-11-18';
    const cleanRoom = newLocation.trim() || 'Room B-214';

    const mappedSchedule = roleSchedule.map((s) => ({
      id: s.id,
      course: s.courseCode,
      date: s.date || DAY_DATE_MAP[s.day] || '2026-11-15',
      start: s.start,
      end: s.end,
      room: s.location,
      teacher: s.lecturer,
      status: 'Scheduled',
      seats: s.enrolled || 0,
      capacity: 120,
    }));

    const validationError = validateRecord(
      'timetable',
      {
        id: 'new',
        course: newCourse,
        date: mappedDate,
        start: newStart,
        end: newEnd,
        room: cleanRoom,
        teacher: profile.name,
        status: 'Scheduled',
        seats: 20,
        capacity: 120,
      },
      null,
      { timetable: mappedSchedule }
    );

    if (validationError) {
      setFormError(validationError);
      return;
    }

    const newItem = {
      id: `tt-${Date.now()}`,
      courseCode: newCourse,
      courseName: courseObj?.name || newCourse,
      courseNameAr: courseObj?.nameAr || newCourse,
      type: newType,
      day: newDay,
      date: mappedDate,
      start: newStart,
      end: newEnd,
      duration: computeMinutesLabel(newStart, newEnd),
      lecturer: profile.name,
      location: cleanRoom,
      buildingId: newBuildingId,
      enrolled: courseObj?.enrolled ?? null,
      // Saved on this device only: the university's timetable comes from the registrar.
      local: true,
      forStaff: true,
      forStudent: newType !== 'Office Hours' && newType !== 'Lab Duty',
    };

    setData((prev) => ({
      ...prev,
      schedule: [...prev.schedule, newItem],
    }));
    setFormError('');
    setAddOpen(false);
    showToast(
      t(
        `Added ${newCourse} ${newType} on ${newDay} (${newStart}–${newEnd}) on this device.`,
        `تمت إضافة ${newCourse} (${newType}) يوم ${newDay} على هذا الجهاز.`
      )
    );
  };

  return (
    <section className="page-enter space-y-6">
      <div className="no-print flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {isStaff
              ? t('FACULTY TEACHING & DUTIES TIMETABLE', 'جدول مهام ومحاضرات عضو هيئة التدريس')
              : t('WEEKLY TIMETABLE & MONTHLY CALENDAR', 'الجدول الأسبوعي والتقويم الشهري')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {isStaff
              ? t('My Teaching Classes & Assigned Duties', 'محاضراتي وساعاتي المكتبية ومهامي')
              : t('Class Schedule & Academic Calendar', 'جدول المحاضرات والتقويم الشخصي')}
          </h1>
          <p className="mt-1 text-xs sm:text-sm text-[#6E645D]">
            {isStaff
              ? t(
                  `Showing only sessions and duties assigned to ${profile.name} (${profile.id}).`,
                  `يعرض فقط المحاضرات والمهام المسندة إلى ${profile.nameAr || profile.name}.`
                )
              : t(
                  'Compare your class timetable alongside the full monthly calendar and track personal reminders.',
                  'استعرض جدولك الأسبوعي بجانب التقويم الشهري الكامل وأضف تذكيراتك الدراسية الخاصة.'
                )}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div
            role="group"
            aria-label={t('Schedule layout mode', 'طريقة عرض الجدول')}
            className="inline-flex rounded-xl border border-[#E8E3D9] bg-white p-1"
          >
            <button
              type="button"
              onClick={() => setViewMode('table')}
              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition ${
                viewMode === 'table'
                  ? 'bg-[#B81104] text-[#FFFACD]'
                  : 'text-[#6E645D] hover:text-[#302521]'
              }`}
            >
              <Table2 className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{t('Table + Calendar', 'الجدول والتقويم')}</span>
            </button>
            <button
              type="button"
              onClick={() => setViewMode('grid')}
              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition ${
                viewMode === 'grid'
                  ? 'bg-[#B81104] text-[#FFFACD]'
                  : 'text-[#6E645D] hover:text-[#302521]'
              }`}
            >
              <LayoutGrid className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{t('Weekly Grid', 'شبكة الأسبوع')}</span>
            </button>
          </div>

          <button
            type="button"
            onClick={handlePrintSchedule}
            className="inline-flex min-h-[40px] items-center gap-1.5 rounded-xl border border-[#B81104]/30 bg-[#FFFACD] px-3.5 py-2 text-xs font-bold text-[#960D03] hover:bg-[#FFF2B5]"
          >
            <Printer className="h-3.5 w-3.5 text-[#B81104]" aria-hidden="true" />
            <span>{t('Print Weekly Schedule', 'طباعة الجدول الأسبوعي')}</span>
          </button>

          <button
            type="button"
            onClick={handleExportICS}
            className="inline-flex min-h-[40px] items-center gap-1.5 rounded-xl border border-[#E8E3D9] bg-white px-3.5 py-2 text-xs font-bold text-[#302521] hover:border-[#B81104]"
          >
            <Download className="h-3.5 w-3.5 text-[#B81104]" aria-hidden="true" />
            <span>{t('Export .ics', 'تصدير التقويم')}</span>
          </button>

          {isStaff ? (
            <button
              type="button"
              onClick={() => {
                setAddOpen((prev) => !prev);
                setFormError('');
              }}
              className="inline-flex min-h-[40px] items-center gap-1.5 rounded-xl bg-[#B81104] px-3.5 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
            >
              <Plus className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{addOpen ? t('Close Form', 'إغلاق') : t('Add Duty / Office Hours', 'إضافة مهمة / ساعات مكتبية')}</span>
            </button>
          ) : null}
        </div>
      </div>

      {/* Filters Row */}
      <div className="no-print cohort-card p-4 flex flex-wrap items-center gap-3">
        <select
          aria-label={t('Filter by course', 'تصفية حسب المقرر')}
          value={courseFilter}
          onChange={(e) => setCourseFilter(e.target.value)}
          className="min-h-[40px] rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] px-3 text-xs font-semibold text-[#302521]"
        >
          <option value="All">{t('All Courses & Duties', 'كل المقررات والمهام')}</option>
          {data.courses.map((c) => (
            <option key={c.id} value={c.id}>
              {c.id} · {lang === 'ar' ? c.nameAr : c.name}
            </option>
          ))}
          {isStaff ? <option value="CS345">CS345 · Operating Systems</option> : null}
          {isStaff ? <option value="ADV">ADV · Academic Advising</option> : null}
        </select>

        <select
          aria-label={t('Filter by day', 'تصفية حسب اليوم')}
          value={dayFilter}
          onChange={(e) => setDayFilter(e.target.value)}
          className="min-h-[40px] rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] px-3 text-xs font-semibold text-[#302521]"
        >
          <option value="All">{t('All Days (Sun–Thu)', 'كل الأيام')}</option>
          {DAYS.map((d) => (
            <option key={d} value={d}>
              {d}
            </option>
          ))}
        </select>

        <div className="flex flex-wrap gap-1.5">
          {availableTypes.map((type) => (
            <button
              key={type}
              type="button"
              onClick={() => setTypeFilter(type)}
              className={`rounded-full border px-3 py-1.5 text-xs font-bold transition ${
                typeFilter === type
                  ? 'border-[#B81104] bg-[#FFFACD] text-[#B81104]'
                  : 'border-[#E8E3D9] bg-white text-[#6E645D]'
              }`}
            >
              {type === 'All' ? t('All Types', 'كل الأنواع') : type}
            </button>
          ))}
        </div>
      </div>

      {/* Staff Add Duty Form */}
      {isStaff && addOpen ? (
        <form onSubmit={handleAddSession} className="no-print cohort-card p-5 space-y-4 border-[#B81104]/30">
          <div className="flex items-center gap-2">
            <CalendarDays className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
            <h2 className="text-sm font-extrabold text-[#302521]">
              {t(
                'Schedule New Faculty Class or Duty (Clash-Checked)',
                'إضافة محاضرة أو مهمة إشرافية جديدة (مع فحص التعارض)'
              )}
            </h2>
          </div>
          <p className="text-xs text-[#6E645D]">
            {t(
              'Sessions you add here are saved on this device only. Your teaching timetable itself comes from the registrar.',
              'الجلسات التي تضيفها هنا تُحفظ على هذا الجهاز فقط. أما جدول تدريسك فيأتي من المسجل.'
            )}
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-6 gap-3">
            <div>
              <label htmlFor="sch-course" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('Course / Duty', 'المقرر / المهمة')}
              </label>
              <select
                id="sch-course"
                value={newCourse}
                onChange={(e) => setNewCourse(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs font-bold"
              >
                {data.courses.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.id}
                  </option>
                ))}
                <option value="CS345">CS345</option>
                <option value="ADV">ADV</option>
              </select>
            </div>

            <div>
              <label htmlFor="sch-type" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('Duty Type', 'نوع المهمة')}
              </label>
              <select
                id="sch-type"
                value={newType}
                onChange={(e) => setNewType(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs font-bold"
              >
                <option value="Office Hours">Office Hours</option>
                <option value="Lecture">Lecture</option>
                <option value="Lab Duty">Lab Duty</option>
              </select>
            </div>

            <div>
              <label htmlFor="sch-day" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('Day', 'اليوم')}
              </label>
              <select
                id="sch-day"
                value={newDay}
                onChange={(e) => setNewDay(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs font-bold"
              >
                {DAYS.map((d) => (
                  <option key={d} value={d}>
                    {d}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label htmlFor="sch-start" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('Start', 'البداية')}
              </label>
              <input
                id="sch-start"
                type="time"
                value={newStart}
                onChange={(e) => setNewStart(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs tabular-nums"
              />
            </div>

            <div>
              <label htmlFor="sch-end" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('End', 'النهاية')}
              </label>
              <input
                id="sch-end"
                type="time"
                value={newEnd}
                onChange={(e) => setNewEnd(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs tabular-nums"
              />
            </div>

            <div>
              <label htmlFor="sch-bldg" className="block text-[11px] font-bold text-[#6E645D] mb-1">
                {t('Building', 'المبنى')}
              </label>
              <select
                id="sch-bldg"
                value={newBuildingId}
                onChange={(e) => setNewBuildingId(e.target.value)}
                className="w-full rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-2 text-xs font-bold"
              >
                {CAMPUS_LOCATIONS.map((b) => (
                  <option key={b.id} value={b.id}>
                    {b.id}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row sm:items-center gap-3">
            <input
              type="text"
              value={newLocation}
              onChange={(e) => setNewLocation(e.target.value)}
              aria-label={t('Room or Hall label', 'رقم القاعة أو الغرفة')}
              placeholder={t('Room / Lab label (e.g., Room B-214)', 'القاعة أو المعمل')}
              className="flex-1 rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs"
            />
            <button
              type="submit"
              className="rounded-xl bg-[#B81104] px-5 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03]"
            >
              {t('Validate & Add Duty', 'فحص التعارض وإضافة الموعد')}
            </button>
          </div>

          {formError ? (
            <div
              role="alert"
              className="flex items-center gap-2 rounded-xl border border-[#C93636]/30 bg-[#FFE9E5] px-4 py-2.5 text-xs font-semibold text-[#9E1C0E]"
            >
              <AlertCircle className="h-4 w-4 shrink-0" aria-hidden="true" />
              <span>{formError}</span>
            </div>
          ) : null}
        </form>
      ) : null}

      {/* Table + Interactive Monthly Calendar Split OR Weekly Grid */}
      {viewMode === 'table' ? (
        <div className="no-print grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          {/* Left: Compact Schedule Table (7 cols) */}
          <div className="lg:col-span-7 cohort-card overflow-hidden">
            <div className="border-b border-[#E8E3D9] bg-[#FCFBF6] px-4 py-3 flex items-center justify-between">
              <h2 className="text-sm font-extrabold text-[#302521]">
                {isStaff
                  ? t('Assigned Faculty Sessions', 'الجلسات والمهام المكلف بها')
                  : t('Enrolled Weekly Schedule', 'جدول الحصص الأسبوعي')}
              </h2>
              <span className="text-[11px] font-bold text-[#B81104] tabular-nums">
                {rows.length} {t('session(s)', 'حصص')}
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-start text-xs sm:text-sm">
                <thead>
                  <tr className="border-b border-[#E8E3D9] bg-[#FCFBF6] text-[11px] text-[#6E645D]">
                    <th className="px-3.5 py-3 font-semibold text-start">
                      {isStaff ? t('Course / Duty', 'المقرر / المهمة') : t('Course & Lead', 'المقرر والمحاضر')}
                    </th>
                    <th className="px-3 py-3 font-semibold text-start">{t('Type', 'النوع')}</th>
                    <th className="px-3 py-3 font-semibold text-start">{t('Day & Time', 'اليوم والوقت')}</th>
                    <th className="px-3.5 py-3 font-semibold text-start">{t('Location', 'الموقع')}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[#E8E3D9]">
                  {rows.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="px-4 py-8 text-center text-xs text-[#6E645D]">
                        {roleSchedule.length === 0
                          ? isStaff
                            ? t('No classes on your timetable yet.', 'لا توجد محاضرات في جدولك بعد.')
                            : t(
                                'No classes yet. The registrar assigns your lecture, lab and tutorial times when you are enrolled.',
                                'لا توجد محاضرات بعد. يحدد المسجل مواعيد محاضراتك ومعاملك وسكاشنك عند تسجيلك.'
                              )
                          : t('No sessions match the selected filters.', 'لا توجد جلسات تطابق عوامل التصفية.')}
                      </td>
                    </tr>
                  ) : (
                    rows.map((row) => (
                      <tr key={row.id} className="hover:bg-[#FCFBF6]">
                        <td className="px-3.5 py-3">
                          <div className="font-bold text-[#302521] text-xs sm:text-sm">
                            {row.courseCode} · {lang === 'ar' ? row.courseNameAr : row.courseName}
                          </div>
                          <div className="text-[11px] text-[#6E645D] mt-0.5">{row.lecturer}</div>
                        </td>
                        <td className="px-3 py-3">
                          <StatusBadge status="Scheduled" label={row.type} />
                        </td>
                        <td className="px-3 py-3 text-xs text-[#302521] tabular-nums whitespace-nowrap">
                          <span className="inline-flex items-center gap-1">
                            <Clock className="h-3.5 w-3.5 text-[#6E645D]" aria-hidden="true" />
                            {row.day} · {row.start}–{row.end}
                          </span>
                          <span className="block text-[10px] text-[#6E645D] mt-0.5">
                            {row.duration}
                          </span>
                        </td>
                        <td className="px-3.5 py-3">
                          <button
                            type="button"
                            onClick={() => navigate('map', { buildingId: row.buildingId })}
                            className="inline-flex items-center gap-1 rounded-lg bg-[#FFFACD] px-2.5 py-1 text-xs font-bold text-[#960D03] hover:bg-[#FFF2B5] whitespace-nowrap"
                          >
                            <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                            <span>{row.location}</span>
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>

          {/* Right: Interactive Monthly Calendar (5 cols) */}
          <div className="lg:col-span-5 cohort-card p-4 sm:p-5 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <CalendarDays className="h-5 w-5 text-[#B81104]" aria-hidden="true" />
                <div>
                  <h2 className="text-sm sm:text-base font-extrabold text-[#302521]">
                    {t('November 2026', 'نوفمبر ٢٠٢٦')}
                  </h2>
                  <p className="text-[11px] text-[#6E645D]">
                    {t(
                      'Tap any day to view appointments, quizzes, assignments & exams',
                      'اضغط على أي يوم لعرض المواعيد والاختبارات والتكليفات'
                    )}
                  </p>
                </div>
              </div>
            </div>

            {/* Compact Legend */}
            <div className="flex flex-wrap gap-2 text-[10px] font-bold text-[#6E645D]">
              <span className="inline-flex items-center gap-1">
                <span className="h-2 w-2 rounded-full bg-[#B76E00]" />
                {t('Assignments', 'تكليفات')}
              </span>
              <span className="inline-flex items-center gap-1">
                <span className="h-2 w-2 rounded-full bg-[#16845B]" />
                {t('Quizzes/Exams', 'اختبارات')}
              </span>
              <span className="inline-flex items-center gap-1">
                <span className="h-2 w-2 rounded-full bg-[#5D514A]" />
                {t('Appointments', 'مواعيد')}
              </span>
              {!isStaff ? (
                <span className="inline-flex items-center gap-1 text-[#960D03]">
                  <span className="h-2 w-2 rounded-full bg-[#7A0B02] ring-2 ring-[#FFFACD]" />
                  {t('My Dates', 'تواريخي')}
                </span>
              ) : null}
            </div>

            {/* 7-Column Month Grid */}
            <div className="space-y-1.5">
              <div className="grid grid-cols-7 gap-1 text-center text-[10px] font-bold text-[#6E645D] uppercase">
                {ALL_WEEKDAYS.map((wd) => (
                  <div key={wd} className="py-1">
                    {wd}
                  </div>
                ))}
              </div>
              <div className="grid grid-cols-7 gap-1">
                {novemberDays.map((cell) => {
                  if (cell.empty) {
                    return <div key={cell.key} className="h-12" />;
                  }
                  const dayEvents = eventsByDate[cell.iso] || [];
                  const isSelected = selectedDate === cell.iso;
                  const isToday = cell.iso === '2026-11-15';
                  const hasPersonal = !isStaff && dayEvents.some((e) => e.kind === 'personal');
                  const dotKinds = Array.from(new Set(dayEvents.map((e) => e.kind))).slice(0, 4);

                  return (
                    <button
                      key={cell.key}
                      type="button"
                      onClick={() => handleSelectCalendarDay(cell.iso)}
                      aria-label={`${cell.iso}, ${dayEvents.length} events`}
                      aria-pressed={isSelected}
                      className={`h-12 rounded-xl border p-1 flex flex-col items-center justify-between transition ${
                        isSelected
                          ? 'border-[#B81104] bg-[#B81104] text-[#FFFACD] shadow-sm'
                          : hasPersonal
                            ? 'border-[#E9DBA9] bg-[#FFFACD]/70 text-[#302521] hover:border-[#B81104]'
                            : isToday
                              ? 'border-[#B81104]/50 bg-[#FFF0ED]/60 text-[#960D03]'
                              : 'border-[#E8E3D9] bg-[#FCFBF6] text-[#302521] hover:border-[#B81104]/40'
                      }`}
                    >
                      <span className="text-xs font-extrabold tabular-nums">{cell.dayNum}</span>
                      <div className="flex items-center gap-0.5 h-2">
                        {dotKinds.map((kind) => (
                          <span
                            key={kind}
                            className={`h-1.5 w-1.5 rounded-full ${
                              isSelected
                                ? 'bg-[#FFFACD]'
                                : EVENT_TYPE_STYLES[kind]?.dot || 'bg-[#6E645D]'
                            }`}
                          />
                        ))}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Selected Date Agenda */}
            <div className="border-t border-[#E8E3D9] pt-3.5 space-y-2.5">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-extrabold text-[#302521] tabular-nums">
                  {t('Agenda for', 'جدول يوم')} {selectedDate}
                </h3>
                <span className="text-[11px] font-bold text-[#B81104] tabular-nums">
                  {selectedDayEvents.length} {t('item(s)', 'عناصر')}
                </span>
              </div>

              {selectedDayEvents.length === 0 ? (
                <p className="rounded-xl border border-dashed border-[#E8E3D9] p-3 text-center text-xs text-[#6E645D]">
                  {t(
                    'No appointments, quizzes, assignments, or exams on this date.',
                    'لا توجد مواعيد أو اختبارات أو تكليفات في هذا اليوم.'
                  )}
                </p>
              ) : (
                <div className="space-y-2 max-h-56 overflow-y-auto pe-1">
                  {selectedDayEvents.map((ev) => {
                    const style = EVENT_TYPE_STYLES[ev.kind] || EVENT_TYPE_STYLES.appointment;
                    return (
                      <div
                        key={ev.id}
                        className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-2.5 flex items-start justify-between gap-2"
                      >
                        <div className="min-w-0">
                          <span
                            className={`inline-block rounded-md border px-1.5 py-0.5 text-[10px] font-bold ${style.chip}`}
                          >
                            {ev.badge}
                          </span>
                          <p className="text-xs font-bold text-[#302521] mt-1">{ev.title}</p>
                          <p className="text-[11px] text-[#6E645D]">{ev.meta}</p>
                        </div>

                        <div className="flex items-center gap-1 shrink-0">
                          {ev.onAction ? (
                            <button
                              type="button"
                              onClick={ev.onAction}
                              className="rounded-lg bg-white border border-[#E8E3D9] px-2 py-1 text-[10px] font-bold text-[#B81104] hover:border-[#B81104]"
                            >
                              {ev.actionLabel}
                            </button>
                          ) : null}
                          {ev.personalId && !isStaff ? (
                            <button
                              type="button"
                              onClick={() => handleDeletePersonalEvent(ev.personalId)}
                              aria-label={t(`Delete ${ev.title}`, `حذف ${ev.title}`)}
                              className="rounded-lg p-1 text-[#C93636] hover:bg-[#FFE9E5]"
                            >
                              <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                            </button>
                          ) : null}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Student-Only Personal Date Form */}
            {!isStaff ? (
              <form
                onSubmit={handleAddPersonalEvent}
                className="border-t border-[#E8E3D9] pt-3.5 space-y-2.5"
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-1.5">
                    <CalendarPlus className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                    <h3 className="text-xs font-extrabold text-[#302521]">
                      {t('Add Personal Calendar Date', 'إضافة موعد شخصي على التقويم')}
                    </h3>
                  </div>
                  <span className="inline-flex items-center gap-1 rounded-full bg-[#FFFACD] border border-[#E9DBA9] px-2 py-0.5 text-[10px] font-bold text-[#960D03]">
                    <Lock className="h-2.5 w-2.5" aria-hidden="true" />
                    {t('Private to you', 'مرئي لك فقط')}
                  </span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  <input
                    type="date"
                    value={personalDate}
                    min="2026-11-01"
                    max="2026-11-30"
                    onChange={(e) => setPersonalDate(e.target.value)}
                    aria-label={t('Personal event date', 'تاريخ الموعد الشخصي')}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-1.5 text-xs tabular-nums"
                  />
                  <input
                    type="time"
                    value={personalTime}
                    onChange={(e) => setPersonalTime(e.target.value)}
                    aria-label={t('Personal event time', 'وقت الموعد الشخصي')}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-1.5 text-xs tabular-nums"
                  />
                  <select
                    value={personalCategory}
                    onChange={(e) => setPersonalCategory(e.target.value)}
                    aria-label={t('Personal event category', 'تصنيف الموعد')}
                    className="rounded-xl border border-[#D6CFC1] bg-white px-2.5 py-1.5 text-xs font-semibold"
                  >
                    <option value="Study Goal">{t('Study Goal', 'هدف دراسي')}</option>
                    <option value="Exam Prep">{t('Exam Prep', 'مراجعة امتحان')}</option>
                    <option value="Personal Reminder">{t('Personal Reminder', 'تذكير شخصي')}</option>
                  </select>
                </div>

                <div className="flex gap-2">
                  <input
                    type="text"
                    value={personalTitle}
                    onChange={(e) => setPersonalTitle(e.target.value)}
                    aria-label={t('Personal calendar note title', 'عنوان التذكير الشخصي')}
                    placeholder={t('Study session, club meeting, or reminder...', 'مذاكرة مادة أو مراجعة أو تذكير خاص...')}
                    className="flex-1 rounded-xl border border-[#D6CFC1] bg-white px-3 py-2 text-xs text-[#302521]"
                  />
                  <button
                    type="submit"
                    className="rounded-xl bg-[#B81104] px-3.5 py-2 text-xs font-bold text-[#FFFACD] hover:bg-[#940E03] whitespace-nowrap"
                  >
                    {t('Set Date', 'إضافة')}
                  </button>
                </div>
              </form>
            ) : null}
          </div>
        </div>
      ) : (
        /* Weekly Grid View */
        <div className="no-print grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
          {DAYS.map((day) => {
            const daySessions = rows
              .filter((r) => r.day === day)
              .sort((a, b) => a.start.localeCompare(b.start));
            return (
              <div key={day} className="cohort-card p-4 space-y-3">
                <div className="flex items-center justify-between border-b border-[#E8E3D9] pb-2">
                  <span className="text-sm font-extrabold text-[#B81104]">{day}</span>
                  <span className="text-[11px] font-bold text-[#6E645D] tabular-nums">
                    {daySessions.length} {t('slot(s)', 'حصص')}
                  </span>
                </div>
                {daySessions.length === 0 ? (
                  <p className="py-4 text-center text-xs text-[#6E645D]">
                    {t('No sessions scheduled', 'لا توجد جلسات')}
                  </p>
                ) : (
                  <div className="space-y-2.5">
                    {daySessions.map((s) => (
                      <div key={s.id} className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3 space-y-1.5">
                        <div className="flex items-center justify-between gap-1.5">
                          <span className="rounded bg-[#FFFACD] px-2 py-0.5 text-[10px] font-extrabold text-[#960D03]">
                            {s.courseCode}
                          </span>
                          <span className="text-[10px] font-bold text-[#6E645D]">{s.type}</span>
                        </div>
                        <p className="text-xs font-bold text-[#302521]">
                          {lang === 'ar' ? s.courseNameAr : s.courseName}
                        </p>
                        <p className="text-[11px] text-[#6E645D] tabular-nums">
                          {s.start}–{s.end}
                        </p>
                        <button
                          type="button"
                          onClick={() => navigate('map', { buildingId: s.buildingId })}
                          className="inline-flex items-center gap-1 text-[11px] font-bold text-[#B81104] hover:underline"
                        >
                          <MapPin className="h-3 w-3" aria-hidden="true" />
                          <span>{s.location}</span>
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Dedicated Printable Weekly Schedule Sheet (Lectures, Labs & Sections) */}
      <div className="print-schedule-sheet hidden print:block space-y-4 text-[#302521]">
        <div className="border-b-2 border-[#B81104] pb-3 flex items-start justify-between gap-4">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-widest text-[#960D03]">
              {t('Cohort University LMS · Weekly Academic Timetable', 'نظام كوهورت الجامعي · الجدول الدراسي الأسبوعي')}
            </p>
            <h2 className="text-xl font-extrabold text-[#302521] mt-0.5">
              {isStaff
                ? t('Faculty Weekly Lectures, Labs & Duties Schedule', 'الجدول الأسبوعي للمحاضرات والمعامل والمهام')
                : t('Student Weekly Lectures, Labs & Sections Schedule', 'الجدول الأسبوعي للمحاضرات والمعامل والسكاشن')}
            </h2>
            <p className="text-xs text-[#6E645D] mt-0.5">
              {lang === 'ar' ? profile.nameAr || profile.name : profile.name} ({profile.id}) ·{' '}
              {lang === 'ar' ? profile.programAr || profile.program : profile.program} ·{' '}
              {t('Fall 2026', 'خريف ٢٠٢٦')}
            </p>
          </div>
          <div className="text-end text-[11px] text-[#6E645D]">
            <div className="inline-block rounded-lg border border-[#E9DBA9] bg-[#FFFACD] px-2.5 py-1 font-bold text-[#960D03]">
              {t('Lectures · Labs · Sections', 'محاضرات · معامل · سكاشن')}
            </div>
            <p className="mt-1 tabular-nums">
              {t('Total Weekly Sessions:', 'إجمالي الجلسات الأسبوعية:')} {roleSchedule.length}
            </p>
          </div>
        </div>

        <table className="w-full border-collapse text-start text-xs">
          <thead>
            <tr className="bg-[#B81104] text-[#FFFACD]">
              <th className="border border-[#960D03] px-3 py-2 font-bold w-24 text-start">
                {t('Day', 'اليوم')}
              </th>
              <th className="border border-[#960D03] px-3 py-2 font-bold text-start">
                {t('Weekly Lectures, Labs & Sections', 'المحاضرات والمعامل والسكاشن الأسبوعية')}
              </th>
            </tr>
          </thead>
          <tbody>
            {DAYS.map((day) => {
              const daySlots = roleSchedule
                .filter((s) => s.day === day)
                .sort((a, b) => a.start.localeCompare(b.start));
              return (
                <tr key={`print-${day}`} className="align-top even:bg-[#FCFBF6]">
                  <td className="border border-[#E8E3D9] px-3 py-2.5 font-extrabold text-[#960D03] bg-[#FFFACD]/45">
                    {day}
                  </td>
                  <td className="border border-[#E8E3D9] p-2">
                    {daySlots.length === 0 ? (
                      <span className="text-[11px] text-[#6E645D]">
                        {t('No scheduled Lectures, Labs, or Sections', 'لا توجد محاضرات أو معامل أو سكاشن')}
                      </span>
                    ) : (
                      <div className="grid grid-cols-3 gap-2">
                        {daySlots.map((slot) => {
                          const badgeClass =
                            slot.type === 'Lecture'
                              ? 'bg-[#FFF0ED] border-[#B81104]/30 text-[#960D03]'
                              : slot.type === 'Lab'
                                ? 'bg-[#FFFACD] border-[#E9DBA9] text-[#960D03]'
                                : 'bg-[#ECFDF5] border-[#16845B]/30 text-[#16845B]';
                          return (
                            <div
                              key={`print-slot-${slot.id}`}
                              className="rounded-lg border border-[#E8E3D9] bg-white p-2 space-y-1"
                            >
                              <div className="flex items-center justify-between gap-1">
                                <span className="font-extrabold text-[#302521]">{slot.courseCode}</span>
                                <span
                                  className={`rounded border px-1.5 py-0.5 text-[10px] font-bold ${badgeClass}`}
                                >
                                  {slot.type}
                                </span>
                              </div>
                              <p className="font-bold text-[#302521] leading-snug">
                                {lang === 'ar' ? slot.courseNameAr : slot.courseName}
                              </p>
                              <p className="text-[11px] text-[#6E645D] tabular-nums">
                                {slot.start}–{slot.end} ({slot.duration})
                              </p>
                              <p className="text-[11px] font-semibold text-[#960D03]">
                                {slot.location} · {slot.lecturer}
                              </p>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>

        <div className="flex items-center justify-between border-t border-[#E8E3D9] pt-2 text-[10px] text-[#6E645D]">
          <span>
            {t(
              'Printed from Cohort Academic LMS · Weekly timetable includes Lectures, Labs, and Sections only.',
              'مطبوع من نظام كوهورت الجامعي · يشمل الجدول الأسبوعي المحاضرات والمعامل والسكاشن.'
            )}
          </span>
          <span className="tabular-nums">2026-11-15</span>
        </div>
      </div>
    </section>
  );
}
