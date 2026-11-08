// Made-up content for the preview tabs. These are plain local types, not API contract types, so
// nobody mistakes any of it for real data. Every name is clearly invented.

export type SampleCourse = { name: string; teacher: string; progress: number; materials: string[] };
export type SampleLesson = { day: string; time: string; title: string; room: string };
export type SampleAssignment = { title: string; course: string; due: string; status: string };
export type SampleConversation = { id: string; with: string; last: string };
export type SampleMessage = { from: string; text: string };
export type SampleTicket = { title: string; status: string; opened: string };
export type SamplePlace = { name: string; kind: string; note: string };

export const sampleCourses: SampleCourse[] = [
  {
    name: "Sample course A",
    teacher: "Sample Teacher One",
    progress: 65,
    materials: ["Sample syllabus", "Sample reading list"],
  },
  {
    name: "Sample course B",
    teacher: "Sample Teacher Two",
    progress: 30,
    materials: ["Sample slides, week 1", "Sample worksheet"],
  },
  {
    name: "Sample course C",
    teacher: "Sample Teacher Three",
    progress: 85,
    materials: ["Sample lab guide"],
  },
];

export const weekDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

export const sampleLessons: SampleLesson[] = [
  { day: "Monday", time: "09:00", title: "Sample course A", room: "Sample Hall 1" },
  { day: "Tuesday", time: "11:00", title: "Sample course B", room: "Sample Hall 2" },
  { day: "Wednesday", time: "09:00", title: "Sample course A", room: "Sample Hall 1" },
  { day: "Thursday", time: "14:00", title: "Sample course C", room: "Sample Lab" },
  { day: "Friday", time: "11:00", title: "Sample course B", room: "Sample Hall 2" },
];

export const sampleAssignments: SampleAssignment[] = [
  { title: "Sample essay", course: "Sample course A", due: "Sample date: next Monday", status: "Not started" },
  { title: "Sample midterm exam", course: "Sample course A", due: "Sample date: in two weeks", status: "Not started" },
  { title: "Sample problem set", course: "Sample course B", due: "Sample date: next Thursday", status: "In progress" },
  { title: "Sample lab report", course: "Sample course C", due: "Sample date: last week", status: "Submitted" },
];

export const sampleConversations: SampleConversation[] = [
  { id: "one", with: "Sample Teacher One", last: "Sample message about the essay" },
  { id: "two", with: "Sample Advisor", last: "Sample reminder about next term" },
  { id: "three", with: "Sample study group", last: "Sample note about the lab" },
];

export const sampleThread: SampleMessage[] = [
  { from: "Sample Teacher One", text: "This is a sample message. Nothing here is real." },
  { from: "You", text: "This is a sample reply." },
];

export const sampleTickets: SampleTicket[] = [
  { title: "Sample request about a locked account", status: "Open", opened: "Sample date: 2 days ago" },
  { title: "Sample request about a timetable clash", status: "Resolved", opened: "Sample date: last month" },
];

export const samplePlaces: SamplePlace[] = [
  { name: "Sample Hall", kind: "Building", note: "Lecture rooms" },
  { name: "Sample Library", kind: "Building", note: "Study space and loans" },
  { name: "Sample Health Centre", kind: "Service", note: "Appointments" },
  { name: "Sample Careers Desk", kind: "Service", note: "Advice and events" },
];

export const sampleQuestion = "When is the sample essay due?";
export const sampleAnswer =
  "This is a sample answer. In the finished product, the assistant would answer from your own courses and deadlines.";
