import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { Link } from "react-router";
import { useApi } from "../lib/ApiContext.tsx";
import { formatEnrollmentStatus, formatGradeItem, formatScore } from "../lib/format.ts";
import { queryKeys } from "../lib/queryKeys.ts";
import "../styles/teaching-assistant-dashboard.css";

function TeachingAssistantDashboard({ displayName }: { displayName: string }) {
  const workspaces = [
    { to: "/courses", icon: "01", title: "Courses & sections", detail: "Review course spaces, teaching materials and section information.", action: "Open courses", tag: "Preview" },
    { to: "/schedule", icon: "02", title: "Teaching schedule", detail: "Keep track of tutorials, labs and upcoming teaching sessions.", action: "View schedule", tag: "Preview" },
    { to: "/assignments", icon: "03", title: "Assignments", detail: "Review assignment information and support student submissions.", action: "Open assignments", tag: "Preview" },
    { to: "/messages", icon: "04", title: "Student communication", detail: "Find the messaging workspace for course-related conversations.", action: "Open messages", tag: "Preview" },
  ];

  return (
    <div className="ta-dashboard">
      <div className="ta-page-heading">
        <div>
          <p className="ta-eyebrow">COHORT · TEACHING WORKSPACE</p>
          <h1>Teaching Assistant</h1>
          <p className="ta-subtitle">Your teaching activity, course resources and student support in one place.</p>
        </div>
        <span className="ta-role-chip"><span aria-hidden="true" /> Teaching team</span>
      </div>

      <section className="ta-hero" aria-labelledby="ta-hero-title">
        <div className="ta-hero-copy">
          <p className="ta-hero-kicker">YOUR UNIVERSITY, IN SYNC</p>
          <h2 id="ta-hero-title">Welcome back, {displayName.split(" ")[0]}.</h2>
          <p>Everything you need to support teaching and help students move forward is within reach.</p>
          <div className="ta-hero-actions">
            <Link className="ta-primary-action" to="/courses">Explore courses <span aria-hidden="true">↗</span></Link>
            <Link className="ta-secondary-action" to="/schedule">View schedule</Link>
          </div>
        </div>
        <div className="ta-hero-art" aria-hidden="true">
          <div className="ta-orbit ta-orbit-one" />
          <div className="ta-orbit ta-orbit-two" />
          <div className="ta-art-card"><span>TA</span><b>Teach<br />together.</b><small>LEARN · SUPPORT · GROW</small></div>
          <i className="ta-art-dot ta-art-dot-one" /><i className="ta-art-dot ta-art-dot-two" />
        </div>
      </section>

      <div className="ta-section-heading">
        <div><p className="ta-eyebrow">GETTING THINGS DONE</p><h2>Your teaching workspace</h2></div>
        <span>Choose where to continue</span>
      </div>

      <section className="ta-workspace-grid" aria-label="Teaching workspaces">
        {workspaces.map((item) => (
          <Link className="ta-workspace-card" to={item.to} key={item.to}>
            <div className="ta-card-top"><span className="ta-card-icon">{item.icon}</span><span className="ta-preview-tag">{item.tag}</span></div>
            <h3>{item.title}</h3>
            <p>{item.detail}</p>
            <span className="ta-card-action">{item.action} <span aria-hidden="true">↗</span></span>
          </Link>
        ))}
      </section>

      <section className="ta-bottom-grid">
        <div className="ta-support-panel">
          <div className="ta-panel-icon" aria-hidden="true">?</div>
          <div><p className="ta-eyebrow">HERE TO HELP</p><h2>Need a hand?</h2><p>Find support resources or send a request to the university team.</p><Link to="/support">Visit support <span aria-hidden="true">↗</span></Link></div>
        </div>
        <div className="ta-note-panel">
          <span className="ta-note-mark" aria-hidden="true">“</span>
          <p>Great teaching happens when students feel supported, prepared and connected.</p>
          <small>THE COHORT TEACHING COMMUNITY</small>
        </div>
      </section>
      <p className="ta-preview-note">Some teaching workspaces are currently previews. Available actions and data depend on your university access.</p>
    </div>
  );
}

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
        <ul className="card-list">
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
        <thead><tr><th scope="col">Course</th><th scope="col">Item</th><th scope="col">Score</th></tr></thead>
        <tbody>
          {grades.data.grades.map((grade) => (
            <tr key={grade.id}><td>{grade.course.code}</td><td>{formatGradeItem(grade)}</td><td>{formatScore(grade.score, grade.maxScore)}</td></tr>
          ))}
        </tbody>
      </table>
    );
  }

  return <section><h2>Published grades</h2>{content}</section>;
}

export function DashboardPage() {
  const api = useApi();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });

  if (me.data?.roles.includes("teaching_assistant")) {
    return <TeachingAssistantDashboard displayName={me.data.displayName} />;
  }

  return <><h1>Dashboard</h1><CoursesSection /><GradesSection /></>;
}
