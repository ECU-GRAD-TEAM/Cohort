import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { Link } from "react-router";
import { useApi } from "../lib/ApiContext.tsx";
import { formatEnrollmentStatus, formatGradeItem, formatScore } from "../lib/format.ts";
import { queryKeys } from "../lib/queryKeys.ts";
import "../styles/teaching-assistant-dashboard.css";

function TeachingAssistantDashboard({ displayName }: { displayName: string }) {
  const firstName = displayName.trim().split(/\s+/)[0] || "there";
  const workspaces = [
    { to: "/courses", title: "Course workspaces", detail: "Open your course spaces and review the information available to you.", action: "Open courses" },
    { to: "/assignments", title: "Assignments", detail: "Find assignment information and the work shared with your courses.", action: "Open assignments" },
    { to: "/schedule", title: "Teaching schedule", detail: "Review your teaching timetable and upcoming sessions.", action: "View schedule" },
    { to: "/messages", title: "Student communication", detail: "Continue course-related conversations with students.", action: "Open messages" },
  ];

  return (
    <div className="uf-dashboard">
      <header className="uf-heading">
        <div><span className="uf-kicker">UNIFLOW / ACADEMIC WORKSPACE</span><h1>Academic Staff Dashboard</h1><p>A clear view of your teaching day.</p></div>
        <span className="uf-demo">Teaching workspace</span>
      </header>

      <section className="uf-hero">
        <div className="uf-hero-copy">
          <span className="uf-kicker">TEACH. CONNECT. INSPIRE.</span>
          <h2>More time for teaching.<br /><em>Everything else, in flow.</em></h2>
          <p>Welcome back, {firstName}. Your courses, schedule and student communication are all within reach.</p>
          <div className="uf-hero-actions"><Link className="uf-primary" to="/courses">Explore courses <span aria-hidden="true">↗</span></Link><Link className="uf-outline" to="/schedule">View schedule</Link></div>
        </div>
        <div className="uf-hero-art" aria-hidden="true"><div className="uf-paper uf-paper-back" /><div className="uf-paper"><span>CS / TA</span><b>Aa<span>+</span></b><i /><i /><i /><div className="uf-paper-check">✓</div></div><span className="uf-art-star">✳</span></div>
      </section>

      <section className="uf-metrics" aria-label="Teaching workspace shortcuts">
        {workspaces.map((item, index) => <Link className="uf-metric" to={item.to} key={item.to}><span className="uf-metric-top"><span>{["01", "02", "03", "04"][index]}</span><span aria-hidden="true">↗</span></span><strong>{item.title}</strong><small>{item.action}</small></Link>)}
      </section>

      <div className="uf-columns">
        <div className="uf-stack">
          <section className="uf-panel">
            <div className="uf-panel-head"><div><span className="uf-kicker">YOUR PRIORITY</span><h2>Review queue</h2></div><span className="uf-muted-label">Staff tools</span></div>
            <div className="uf-empty"><span aria-hidden="true">✓</span><p>There are no review items available in this workspace yet.</p></div>
          </section>

          <section className="uf-panel">
            <div className="uf-panel-head"><div><span className="uf-kicker">COURSE OVERVIEW</span><h2>Your teaching space</h2></div><Link to="/courses">View all ↗</Link></div>
            <div className="uf-course-grid">{workspaces.slice(0, 2).map((item, index) => <Link className="uf-course" to={item.to} key={item.to}><div className={`uf-course-cover uf-cover-${index}`}><span>{index === 0 ? "COURSES" : "ASSESSMENTS"}</span><b>{index === 0 ? "01" : "02"}</b></div><div className="uf-course-body"><h3>{item.title}</h3><p>{item.detail}</p><span>{item.action} ↗</span></div></Link>)}</div>
          </section>

          <section className="uf-panel uf-shortcuts"><span className="uf-kicker">QUICK ACTIONS</span><h2>Prepare your next teaching session</h2><div>{workspaces.slice(0, 3).map((item, index) => <Link to={item.to} key={item.to}><span>{["01", "02", "03"][index]}</span><b>{item.action}</b><span aria-hidden="true">↗</span></Link>)}</div></section>
        </div>

        <aside className="uf-stack">
          <section className="uf-panel uf-planner"><div className="uf-panel-head"><div><span className="uf-kicker">PLAN YOUR TEACHING</span><h2>Teaching schedule</h2></div><Link to="/schedule">View all ↗</Link></div><p className="uf-caption">Your timetable and upcoming teaching sessions.</p><div className="uf-empty uf-compact"><span aria-hidden="true">◷</span><p>Schedule details will appear here when available.</p></div><Link className="uf-wide" to="/schedule">Open schedule <span>↗</span></Link></section>

          <section className="uf-panel uf-lemon"><span className="uf-kicker">ASSESSMENT & RESOURCES</span><h2>Everything in one place.</h2><p>Access course information, assignments and learning resources through your teaching workspace.</p><Link to="/assignments">Explore assignments ↗</Link><Link to="/courses">Browse course resources ↗</Link></section>

          <section className="uf-panel uf-support"><span className="uf-tool-mark">?</span><span className="uf-kicker">HERE TO HELP</span><h2>Teaching support</h2><p>Find support resources or send a request to the university team.</p><Link to="/support">Visit support ↗</Link></section>
        </aside>
      </div>
      <p className="uf-footnote">Staff-specific records and teaching actions appear only when supported by your university access.</p>
    </div>
  );
}

function CoursesSection() {
  const api = useApi();
  const enrollments = useQuery({ queryKey: queryKeys.enrollments, queryFn: () => api.getMyEnrollments() });
  let content: ReactNode;
  if (enrollments.isPending) content = <p>Loading…</p>;
  else if (enrollments.data === undefined) content = <p role="alert">{enrollments.error?.message}</p>;
  else {
    const current = enrollments.data.enrollments.filter((enrollment) => enrollment.status !== "dropped");
    content = current.length === 0 ? <p>You are not registered in any courses yet.</p> : <ul className="card-list">{current.map((enrollment) => <li key={enrollment.id}>{`${enrollment.course.code} ${enrollment.course.title} · Section ${enrollment.sectionCode} · ${formatEnrollmentStatus(enrollment.status, enrollment.waitlistPosition)}`}</li>)}</ul>;
  }
  return <section><h2>My courses</h2>{content}</section>;
}

function GradesSection() {
  const api = useApi();
  const grades = useQuery({ queryKey: queryKeys.grades, queryFn: () => api.getMyGrades() });
  let content: ReactNode;
  if (grades.isPending) content = <p>Loading…</p>;
  else if (grades.data === undefined) content = <p role="alert">{grades.error?.message}</p>;
  else if (grades.data.grades.length === 0) content = <p>No published grades yet.</p>;
  else content = <table><thead><tr><th scope="col">Course</th><th scope="col">Item</th><th scope="col">Score</th></tr></thead><tbody>{grades.data.grades.map((grade) => <tr key={grade.id}><td>{grade.course.code}</td><td>{formatGradeItem(grade)}</td><td>{formatScore(grade.score, grade.maxScore)}</td></tr>)}</tbody></table>;
  return <section><h2>Published grades</h2>{content}</section>;
}

export function DashboardPage() {
  const api = useApi();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });
  if (me.data?.roles.includes("teaching_assistant")) return <TeachingAssistantDashboard displayName={me.data.displayName} />;
  return <><h1>Dashboard</h1><CoursesSection /><GradesSection /></>;
}
