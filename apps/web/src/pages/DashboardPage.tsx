import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { useApi } from "../lib/ApiContext.tsx";
import { formatEnrollmentStatus, formatGradeItem, formatScore } from "../lib/format.ts";
import { queryKeys } from "../lib/queryKeys.ts";

function CoursesSection() {
  const api = useApi();
  const enrollments = useQuery({ queryKey: queryKeys.enrollments, queryFn: () => api.getMyEnrollments() });

  let content: ReactNode;
  if (enrollments.isPending) {
    content = <p>Loading…</p>;
  } else if (enrollments.data === undefined) {
    content = <p role="alert">{enrollments.error?.message}</p>;
  } else {
    const current = enrollments.data.enrollments.filter((enrollment) => enrollment.status !== "dropped");
    content =
      current.length === 0 ? (
        <p>You are not registered in any courses yet.</p>
      ) : (
        <ul>
          {current.map((enrollment) => (
            <li key={enrollment.id}>
              {`${enrollment.course.code} ${enrollment.course.title} · Section ${enrollment.sectionCode} · ${formatEnrollmentStatus(enrollment.status, enrollment.waitlistPosition)}`}
            </li>
          ))}
        </ul>
      );
  }

  return (
    <section>
      <h2>My courses</h2>
      {content}
    </section>
  );
}

function GradesSection() {
  const api = useApi();
  const grades = useQuery({ queryKey: queryKeys.grades, queryFn: () => api.getMyGrades() });

  let content: ReactNode;
  if (grades.isPending) {
    content = <p>Loading…</p>;
  } else if (grades.data === undefined) {
    content = <p role="alert">{grades.error?.message}</p>;
  } else if (grades.data.grades.length === 0) {
    content = <p>No published grades yet.</p>;
  } else {
    content = (
      <table>
        <thead>
          <tr>
            <th scope="col">Course</th>
            <th scope="col">Item</th>
            <th scope="col">Score</th>
          </tr>
        </thead>
        <tbody>
          {grades.data.grades.map((grade) => (
            <tr key={grade.id}>
              <td>{grade.course.code}</td>
              <td>{formatGradeItem(grade)}</td>
              <td>{formatScore(grade.score, grade.maxScore)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    );
  }

  return (
    <section>
      <h2>Published grades</h2>
      {content}
    </section>
  );
}

export function DashboardPage() {
  return (
    <>
      <h1>Dashboard</h1>
      <CoursesSection />
      <GradesSection />
    </>
  );
}
