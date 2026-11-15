import assert from 'node:assert/strict';
import { validateRecord, validateCourseRegistration, parseCSV } from '../src/utils/validation.js';
import { INITIAL_SEED } from '../src/data/seedData.js';

const mockDb = {
  users: [{ id: 'u1', email: 'alex@example.edu' }],
  timetable: [
    {
      id: 't1',
      status: 'Published',
      date: '2026-10-28',
      start: '09:00',
      end: '10:15',
      room: 'Engineering 101',
      teacher: 'Michael Tan',
      course: 'CS201',
    },
  ],
};

assert.match(validateRecord('users', { email: 'ALEX@example.edu' }, null, mockDb), /already exists/);
assert.match(validateRecord('offerings', { enrolled: 46, capacity: 45 }, null, mockDb), /exceed/);
assert.match(
  validateRecord('offerings', { code: 'CS201', prerequisite: 'CS201' }, null, mockDb),
  /own prerequisite/
);

const lesson = {
  date: '2026-10-28',
  start: '09:30',
  end: '10:30',
  room: 'Engineering 101',
  teacher: 'Other',
  course: 'CS305',
  capacity: 50,
  seats: 42,
  status: 'Draft',
};

assert.match(validateRecord('timetable', lesson, null, mockDb), /Schedule conflict/);
assert.equal(validateRecord('timetable', { ...lesson, start: '10:15', end: '11:15' }, null, mockDb), '');
assert.match(validateRecord('timetable', { ...lesson, seats: 51 }, null, mockDb), /capacity/);
assert.match(validateRecord('incidents', { status: 'Resolved', notes: 'done' }, null, mockDb), /notes/);
assert.match(
  validateRecord('questions', { type: 'Multiple choice', options: 'A\nB', answer: '2' }, null, mockDb),
  /valid/
);
assert.equal(
  validateRecord('questions', { type: 'Multiple choice', options: 'A\nB', answer: '1' }, null, mockDb),
  ''
);

assert.deepEqual(
  parseCSV('name,email\r\n"Alex, C",alex@example.edu\r\n'),
  [
    ['name', 'email'],
    ['Alex, C', 'alex@example.edu'],
  ]
);
assert.throws(() => parseCSV('name\n"broken'), /unclosed/);

// Course registration rules (7-course cap & time clashes)
const sevenCourses = Array.from({ length: 7 }, (_, i) => ({
  courseCode: `C${i + 1}`,
  status: 'Approved',
  slots: [],
}));
assert.match(
  validateCourseRegistration({
    offering: { code: 'CS401', prerequisite: '' },
    existingRegistrations: sevenCourses,
  }),
  /maximum of 7 courses/
);
assert.match(
  validateCourseRegistration({
    offering: { code: 'CS350', prerequisite: 'CS201' },
    existingRegistrations: [],
    completedPrerequisites: ['CS101'],
  }),
  /Missing prerequisite/
);
assert.match(
  validateCourseRegistration({
    offering: { code: 'CS320', prerequisite: '' },
    selectedSlots: [{ courseCode: 'CS320', type: 'Lecture', day: 'Mon', start: '09:30', end: '10:30' }],
    existingRegistrations: [
      {
        courseCode: 'CS201',
        status: 'Approved',
        slots: [{ courseCode: 'CS201', type: 'Lecture', day: 'Mon', start: '09:00', end: '10:15' }],
      },
    ],
  }),
  /Time clash/
);

// Phase 5 Seed Integrity Checks across Student, Academic Staff, Question Types & Chat Channels
const seededQuestionTypes = new Set(
  [...INITIAL_SEED.assignments, ...INITIAL_SEED.quizzes]
    .flatMap((item) => item.questions || [])
    .map((q) => q.type)
);
for (const expectedType of ['MCQ', 'True/False', 'Written', 'Match', 'Fill in the blanks']) {
  assert.ok(seededQuestionTypes.has(expectedType), `Missing seeded question type: ${expectedType}`);
}

assert.ok(INITIAL_SEED.profiles.Student && INITIAL_SEED.profiles['Academic Staff'], 'Both role profiles must exist');
assert.ok(INITIAL_SEED.prefs.Student && INITIAL_SEED.prefs['Academic Staff'], 'Both role prefs must exist');
assert.ok(INITIAL_SEED.schedule.some((s) => s.forStudent), 'Student schedule entries must exist');
assert.ok(INITIAL_SEED.schedule.some((s) => s.forStaff), 'Academic Staff schedule entries must exist');

for (const threadKey of ['advisor-leila', 'direct-p-alex', 'direct-p-michael', 'course-CS201', 'direct-p-elena']) {
  assert.ok(
    Array.isArray(INITIAL_SEED.chatThreads[threadKey]) && INITIAL_SEED.chatThreads[threadKey].length > 0,
    `Missing chat thread seed: ${threadKey}`
  );
}

console.log(
  '23 validation assertions passed: validation rules, 7-course cap, registration clashes, all 5 interactive question types, role profiles/schedules, and multi-channel chat threads.'
);
