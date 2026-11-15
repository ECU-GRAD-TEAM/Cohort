/**
 * Business-rule validation and CSV parsing utilities for Cohort LMS.
 */

export function validateRecord(kind, r, old = null, db = { users: [], timetable: [] }) {
  if (r.end && r.start && r.end <= r.start) {
    return 'End must be after start.';
  }
  if (
    kind === 'users' &&
    (db.users || []).some(
      (u) => u.id !== old?.id && u.email.toLowerCase() === String(r.email || '').toLowerCase()
    )
  ) {
    return 'This email already exists in the local directory.';
  }
  if (kind === 'offerings' && Number(r.enrolled) > Number(r.capacity)) {
    return 'Enrolled students cannot exceed section capacity.';
  }
  if (kind === 'offerings' && r.prerequisite && r.prerequisite === r.code) {
    return 'A course cannot be its own prerequisite.';
  }
  if (kind === 'timetable') {
    if (Number(r.seats) > Number(r.capacity)) {
      return 'Class size exceeds room capacity.';
    }
    const clash = (db.timetable || []).find(
      (t) =>
        t.id !== old?.id &&
        t.status !== 'Archived' &&
        r.status !== 'Archived' &&
        t.date === r.date &&
        r.start < t.end &&
        r.end > t.start &&
        (String(t.room).toLowerCase() === String(r.room || '').toLowerCase() ||
          String(t.teacher).toLowerCase() === String(r.teacher || '').toLowerCase() ||
          t.course === r.course)
    );
    if (clash) {
      return `Schedule conflict with ${clash.course}, ${clash.start}–${clash.end} in ${clash.room}. Choose another time, room or instructor.`;
    }
  }
  if (kind === 'incidents' && r.status === 'Resolved' && String(r.notes || '').trim().length < 10) {
    return 'Add meaningful resolution notes before resolving the incident.';
  }
  if (kind === 'questions') {
    if (['Multiple choice', 'True / false'].includes(r.type)) {
      const opts =
        r.type === 'True / false'
          ? ['True', 'False']
          : String(r.options || '')
              .split('\n')
              .filter(Boolean);
      if (opts.length < 2 || !/^\d+$/.test(String(r.answer)) || Number(r.answer) >= opts.length) {
        return 'Add at least two options and a valid zero-based correct option index.';
      }
      if (r.type === 'True / false') {
        r.options = 'True\nFalse';
      }
    }
    if (
      r.type === 'Matching' &&
      !String(r.options || '')
        .split('\n')
        .filter(Boolean)
        .every((x) => x.includes('=') && x.split('=').every((t) => t.trim()))
    ) {
      return 'Use one matching pair per line: left = right.';
    }
  }
  return '';
}

export function validateCourseRegistration({
  offering,
  selectedSlots = [],
  existingRegistrations = [],
  completedPrerequisites = [],
}) {
  if (!offering) return 'Select a valid course offering.';
  if (existingRegistrations.some((r) => r.courseCode === offering.code && r.status !== 'Withdrawn')) {
    return `${offering.code} is already in your registration list.`;
  }
  const activeCount = existingRegistrations.filter((r) => r.status !== 'Withdrawn').length;
  if (activeCount >= 7) {
    return 'Registration limit reached: a maximum of 7 courses per term is allowed.';
  }
  if (offering.prerequisite && !completedPrerequisites.includes(offering.prerequisite)) {
    return `Missing prerequisite: ${offering.prerequisite} must be completed before registering for ${offering.code}.`;
  }
  // Check Lecture / Lab / Section time conflicts against already registered slots
  const registeredSlots = existingRegistrations
    .filter((r) => r.status !== 'Withdrawn')
    .flatMap((r) => r.slots || []);

  for (const nextSlot of selectedSlots) {
    for (const prevSlot of registeredSlots) {
      if (
        nextSlot.day === prevSlot.day &&
        nextSlot.start < prevSlot.end &&
        nextSlot.end > prevSlot.start
      ) {
        return `Time clash on ${nextSlot.day} (${nextSlot.start}–${nextSlot.end}) with ${prevSlot.courseCode} ${prevSlot.type}.`;
      }
    }
  }
  return '';
}

export function parseCSV(text) {
  const rows = [];
  let row = [];
  let v = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') {
        v += '"';
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c === ',' && !quoted) {
      row.push(v);
      v = '';
    } else if ((c === '\n' || c === '\r') && !quoted) {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(v);
      if (row.some((cell) => cell.trim())) rows.push(row);
      row = [];
      v = '';
    } else {
      v += c;
    }
  }
  row.push(v);
  if (row.some((cell) => cell.trim())) rows.push(row);
  if (quoted) throw new Error('CSV contains an unclosed quoted field.');
  return rows;
}
