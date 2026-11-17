// Turns the API's answers into the shapes the pages already use (data.courses, data.schedule and
// the profile), so the pages read real data without being rewritten. Plain JavaScript with no
// browser or build dependencies, so tests/live-data.mjs can run it under Node.

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const ACCENTS = ['#FFF2B5', '#DDEBFF', '#E3F4E8', '#FCE4EC', '#EDE7F6', '#FFE9D6'];

/** Role keys a university gives its students. */
export const STUDENT_ROLES = ['undergraduate', 'postgraduate'];

/**
 * Which workspace a person sees: Student with a student role, Academic Staff for any other staff
 * account. A non-staff account without a student role sees the student workspace, empty.
 */
export function workspaceRole(me) {
  if (me.roles.some((role) => STUDENT_ROLES.includes(role))) return 'Student';
  return me.userType === 'staff' ? 'Academic Staff' : 'Student';
}

function minutes(clock) {
  const [h, m] = clock.split(':').map(Number);
  return h * 60 + m;
}

function capitalize(word) {
  return word ? word[0].toUpperCase() + word.slice(1) : word;
}

/** The date (YYYY-MM-DD) of the given ISO weekday in the week of `today`, Monday first. */
export function dateInWeek(weekday, today = new Date()) {
  const todayIso = ((today.getDay() + 6) % 7) + 1;
  const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + (weekday - todayIso));
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** /me/schedule meetings as timetable slots. */
export function toScheduleItems(meetings, today = new Date()) {
  return meetings.map((m) => ({
    id: m.id,
    courseCode: m.course.code,
    courseName: m.course.title,
    courseNameAr: m.course.title,
    sectionCode: m.section.code,
    type: capitalize(m.type),
    day: DAYS[m.weekday - 1],
    date: dateInWeek(m.weekday, today),
    start: m.startsAt,
    end: m.endsAt,
    duration: `${minutes(m.endsAt) - minutes(m.startsAt)} min`,
    lecturer: m.instructors.join(', ') || '—',
    location: [m.room, m.building].filter(Boolean).join(' · ') || '—',
    buildingId: null,
    enrolled: null,
    forStudent: m.role === 'student',
    forStaff: m.role === 'teacher',
  }));
}

/** Each course's published grades averaged as a percentage, or null without any. */
function averageByCourse(grades) {
  const sums = new Map();
  for (const g of grades) {
    const entry = sums.get(g.course.code) ?? { total: 0, count: 0 };
    entry.total += (g.score / g.maxScore) * 100;
    entry.count += 1;
    sums.set(g.course.code, entry);
  }
  return new Map([...sums].map(([code, { total, count }]) => [code, Math.round(total / count)]));
}

function teachersOf(meetings, code, types) {
  const names = new Set();
  for (const m of meetings) {
    if (m.course.code === code && types.includes(m.type)) m.instructors.forEach((name) => names.add(name));
  }
  return [...names].join(', ');
}

function courseCard(index, code, title, credits) {
  return {
    id: code,
    name: title,
    nameAr: title,
    credits,
    accent: ACCENTS[index % ACCENTS.length],
    symbol: code.replace(/[^A-Z]/gi, '').slice(0, 3) || '{ }',
    topic: '',
    topicAr: '',
    progress: null,
    attendance: null,
  };
}

/** A student's current courses: enrolled or waitlisted, from /me/enrollments, /me/grades and /me/schedule. */
export function toStudentCourses(enrollments, grades, meetings) {
  const averages = averageByCourse(grades);
  return enrollments
    .filter((e) => e.status === 'enrolled' || e.status === 'waitlisted')
    .map((e, i) => ({
      ...courseCard(i, e.course.code, e.course.title, e.course.creditHours),
      teacher: teachersOf(meetings, e.course.code, ['lecture']) || '—',
      ta: teachersOf(meetings, e.course.code, ['lab', 'tutorial']) || '—',
      grade: averages.get(e.course.code) ?? null,
      section: e.sections.map((s) => s.code).join(', ') || '—',
      enrolled: null,
      capacity: null,
      status: e.status,
      waitlistPosition: e.waitlistPosition,
    }));
}

/** A teacher's courses: the sections from /me/teaching, grouped by course. */
export function toStaffCourses(sections, teacherName) {
  const byCode = new Map();
  for (const s of sections) {
    const course = byCode.get(s.course.code) ?? { ...s.course, sections: [], students: 0, capacity: 0, open: false };
    course.sections.push(s.code);
    course.students += s.students;
    if (s.capacity === null) course.open = true;
    else course.capacity += s.capacity;
    byCode.set(s.course.code, course);
  }
  return [...byCode.values()].map((c, i) => ({
    ...courseCard(i, c.code, c.title, c.creditHours),
    teacher: teacherName,
    ta: '—',
    grade: null,
    section: c.sections.join(', '),
    enrolled: c.students,
    capacity: c.open ? null : c.capacity,
  }));
}

/** The signed-in person's profile, in the profile shape the pages use; unknown fields are empty. */
export function toProfile(me, role) {
  const base = {
    id: '',
    name: me.displayName,
    nameAr: me.displayName,
    email: me.email,
    phone: '',
    university: me.tenant.name,
  };
  if (role === 'Academic Staff') {
    return { ...base, department: me.tenant.name, departmentAr: me.tenant.name, rank: '', rankAr: '', officeRoom: '', officeRoomAr: '', officeHoursNote: '', officeHoursNoteAr: '', advisorRole: '', advisorRoleAr: '' };
  }
  return { ...base, programme: me.tenant.name, programmeAr: me.tenant.name, year: '', yearAr: '', advisor: '', advisorAr: '', standing: '', standingAr: '' };
}
