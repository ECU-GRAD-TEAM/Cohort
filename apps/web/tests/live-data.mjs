// Checks that API answers become the shapes the pages read. Run with: node tests/live-data.mjs
import assert from 'node:assert/strict';
import {
  dateInWeek,
  toProfile,
  toScheduleItems,
  toStaffCourses,
  toStudentCourses,
  workspaceRole,
} from '../src/lib/liveData.js';

let passed = 0;
const check = (name, fn) => {
  fn();
  passed += 1;
};

const me = (roles, userType = 'non_staff') => ({
  id: '00000000-0000-4000-8000-000000000001',
  email: 'sara@ecu.edu.eg',
  userType,
  displayName: 'Sara Student',
  tenant: { id: '00000000-0000-4000-8000-0000000000aa', name: 'Egyptian Chinese University' },
  roles,
});

check('students see the student workspace, other staff the staff one', () => {
  assert.equal(workspaceRole(me(['undergraduate'])), 'Student');
  assert.equal(workspaceRole(me(['postgraduate'])), 'Student');
  assert.equal(workspaceRole(me(['instructor'], 'staff')), 'Academic Staff');
  assert.equal(workspaceRole(me(['it_officer'], 'staff')), 'Academic Staff');
  assert.equal(workspaceRole(me([], 'non_staff')), 'Student');
  assert.equal(workspaceRole(me(['undergraduate', 'teaching_assistant'], 'staff')), 'Student');
});

check('dateInWeek finds the weekday in the same Monday-first week', () => {
  const wednesday = new Date(2026, 10, 18); // Wed 18 Nov 2026
  assert.equal(dateInWeek(1, wednesday), '2026-11-16');
  assert.equal(dateInWeek(3, wednesday), '2026-11-18');
  assert.equal(dateInWeek(7, wednesday), '2026-11-22');
});

const meeting = (over = {}) => ({
  id: 'm1',
  type: 'lecture',
  weekday: 7,
  startsAt: '09:00',
  endsAt: '10:30',
  room: '101',
  building: 'Main Building',
  course: { code: 'CS101', title: 'Programming I' },
  section: { id: 's1', code: 'L1' },
  instructors: ['Tariq Teacher'],
  role: 'student',
  ...over,
});

check('meetings become timetable slots', () => {
  const [slot] = toScheduleItems([meeting()], new Date(2026, 10, 18));
  assert.deepEqual(slot, {
    id: 'm1',
    courseCode: 'CS101',
    courseName: 'Programming I',
    courseNameAr: 'Programming I',
    sectionCode: 'L1',
    type: 'Lecture',
    day: 'Sun',
    date: '2026-11-22',
    start: '09:00',
    end: '10:30',
    duration: '90 min',
    lecturer: 'Tariq Teacher',
    location: '101 · Main Building',
    buildingId: null,
    enrolled: null,
    forStudent: true,
    forStaff: false,
  });
  const [bare] = toScheduleItems([meeting({ room: null, building: null, instructors: [], role: 'teacher' })]);
  assert.equal(bare.location, '—');
  assert.equal(bare.lecturer, '—');
  assert.equal(bare.forStaff, true);
});

check('a student sees current courses with teachers, sections and average grade', () => {
  const enrollment = (code, status, sections = [{ id: 's1', code: 'L1' }]) => ({
    id: code,
    termId: 't1',
    status,
    waitlistPosition: status === 'waitlisted' ? 2 : null,
    course: { code, title: `${code} title`, creditHours: 3 },
    sections,
  });
  const courses = toStudentCourses(
    [enrollment('CS101', 'enrolled'), enrollment('CS201', 'waitlisted', []), enrollment('MA101', 'dropped'), enrollment('PH101', 'completed')],
    [
      { course: { code: 'CS101' }, score: 30, maxScore: 40 },
      { course: { code: 'CS101' }, score: 9, maxScore: 10 },
    ],
    [meeting(), meeting({ id: 'm2', type: 'lab', instructors: ['Lina TA'] })],
  );
  assert.deepEqual(courses.map((c) => c.id), ['CS101', 'CS201']);
  assert.equal(courses[0].grade, 83);
  assert.equal(courses[0].teacher, 'Tariq Teacher');
  assert.equal(courses[0].ta, 'Lina TA');
  assert.equal(courses[0].section, 'L1');
  assert.equal(courses[1].grade, null);
  assert.equal(courses[1].section, '—');
  assert.equal(courses[1].waitlistPosition, 2);
  assert.equal(courses[0].progress, null);
  assert.equal(courses[0].attendance, null);
});

check('a teacher sees one card per course, with students and capacity summed across sections', () => {
  const section = (code, courseCode, students, capacity) => ({
    id: `${courseCode}-${code}`,
    code,
    kind: 'lecture',
    capacity,
    termId: 't1',
    course: { code: courseCode, title: `${courseCode} title`, creditHours: 3 },
    students,
  });
  const courses = toStaffCourses(
    [section('L1', 'CS101', 20, 30), section('L2', 'CS101', 5, 30), section('L1', 'CS201', 7, null)],
    'Tariq Teacher',
  );
  assert.deepEqual(
    courses.map((c) => [c.id, c.section, c.enrolled, c.capacity, c.teacher]),
    [
      ['CS101', 'L1, L2', 25, 60, 'Tariq Teacher'],
      ['CS201', 'L1', 7, null, 'Tariq Teacher'],
    ],
  );
});

check('the profile carries the real name, email and university, and nothing invented', () => {
  const profile = toProfile(me(['undergraduate']), 'Student');
  assert.equal(profile.name, 'Sara Student');
  assert.equal(profile.email, 'sara@ecu.edu.eg');
  assert.equal(profile.programme, 'Egyptian Chinese University');
  assert.equal(profile.advisor, '');
  assert.equal(profile.phone, '');
});

console.log(`${passed} live-data checks passed.`);
