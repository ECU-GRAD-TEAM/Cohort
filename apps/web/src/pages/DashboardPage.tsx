import { Link } from "react-router";
import { useQuery } from "@tanstack/react-query";
import { useApi } from "../lib/ApiContext.tsx";
import { queryKeys } from "../lib/queryKeys.ts";
import "../styles/teaching-assistant-dashboard.css";

const workspaces = [
  { to: "/courses", number: "01", title: "Courses & sections", detail: "Open your course spaces and find the information you need for each section.", action: "Explore courses" },
  { to: "/assignments", number: "02", title: "Assignments", detail: "Keep assignment information and student work within easy reach.", action: "Open assignments" },
  { to: "/schedule", number: "03", title: "Teaching schedule", detail: "Review your teaching timetable and upcoming sessions.", action: "View schedule" },
  { to: "/messages", number: "04", title: "Student communication", detail: "Continue course-related conversations and keep in touch.", action: "Open messages" },
];

function TeachingStaffDashboard({ displayName }: { displayName: string }) {
  return (
    <div className="ta-dashboard">
      <div className="ta-page-heading">
        <div>
          <p className="ta-eyebrow">COHORT / ACADEMIC WORKSPACE</p>
          <h1>Academic Staff Dashboard</h1>
          <p className="ta-subtitle">A clear view of your teaching day.</p>
        </div>
        <span className="ta-role-chip"><span aria-hidden="true" /> Teaching workspace</span>
      </div>

      <section className="ta-hero" aria-labelledby="ta-hero-title">
        <div className="ta-hero-copy">
          <p className="ta-hero-kicker">TEACH. CONNECT. INSPIRE.</p>
          <h2 id="ta-hero-title">More time for teaching.<br /><em>Everything else, in flow.</em></h2>
          <p>Welcome back, {displayName.split(" ")[0]}. Your courses, schedule and student communication are all within reach.</p>
          <div className="ta-hero-actions">
            <Link className="ta-primary-action" to="/courses">Explore courses <span aria-hidden="true">↗</span></Link>
            <Link className="ta-secondary-action" to="/schedule">View schedule</Link>
          </div>
        </div>
        <div className="ta-hero-art" aria-hidden="true">
          <div className="ta-orbit ta-orbit-one" />
          <div className="ta-orbit ta-orbit-two" />
          <div className="ta-art-card"><span>COHORT</span><b>Teach<br />together.</b><small>LEARN · SUPPORT · GROW</small></div>
          <i className="ta-art-dot ta-art-dot-one" /><i className="ta-art-dot ta-art-dot-two" />
        </div>
      </section>

      <section className="ta-metrics" aria-label="Teaching workspaces">
        {workspaces.map((item) => (
          <Link className="ta-metric" to={item.to} key={item.to}>
            <span className="ta-metric-top"><span>{item.number}</span><span aria-hidden="true">↗</span></span>
            <strong>{item.title}</strong>
            <small>Open workspace</small>
          </Link>
        ))}
      </section>

      <div className="ta-content-grid">
        <div className="ta-main-column">
          <section className="ta-panel">
            <div className="ta-panel-heading">
              <div><p className="ta-eyebrow">YOUR TEACHING SPACE</p><h2>Continue where you left off</h2></div>
              <Link to="/courses">View courses ↗</Link>
            </div>
            <div className="ta-workspace-grid" aria-label="Teaching workspaces">
              {workspaces.slice(0, 2).map((item) => (
                <Link className="ta-workspace-card" to={item.to} key={item.to}>
                  <div className="ta-card-top"><span className="ta-card-icon">{item.number}</span><span className="ta-preview-tag">Preview</span></div>
                  <h3>{item.title}</h3>
                  <p>{item.detail}</p>
                  <span className="ta-card-action">{item.action} <span aria-hidden="true">↗</span></span>
                </Link>
              ))}
            </div>
          </section>

          <section className="ta-panel ta-shortcuts">
            <div className="ta-panel-heading">
              <div><p className="ta-eyebrow">QUICK ACCESS</p><h2>Your teaching tools</h2></div>
            </div>
            <div className="ta-shortcut-grid">
              {workspaces.slice(1).map((item) => (
                <Link to={item.to} key={item.to}><span>{item.number}</span><b>{item.title}</b><span aria-hidden="true">↗</span></Link>
              ))}
            </div>
          </section>
        </div>

        <aside className="ta-side-column">
          <section className="ta-panel ta-planner">
            <div className="ta-panel-heading">
              <div><p className="ta-eyebrow">PLAN YOUR TEACHING</p><h2>Teaching schedule</h2></div>
              <Link to="/schedule">View all ↗</Link>
            </div>
            <p className="ta-panel-copy">Keep your teaching day organised and review the sessions available in your schedule workspace.</p>
            <Link className="ta-wide-action" to="/schedule">Open schedule <span aria-hidden="true">↗</span></Link>
          </section>

          <section className="ta-panel ta-lemon">
            <p className="ta-eyebrow">COURSE RESOURCES</p>
            <h2>Everything in one place.</h2>
            <p>Find course spaces, teaching materials and section information from your courses workspace.</p>
            <Link to="/courses">Explore course resources ↗</Link>
          </section>

          <section className="ta-panel ta-support">
            <span className="ta-support-mark" aria-hidden="true">?</span>
            <p className="ta-eyebrow">HERE TO HELP</p>
            <h2>Need a hand?</h2>
            <p>Find support resources or send a request to the university team.</p>
            <Link to="/support">Visit support ↗</Link>
          </section>
        </aside>
      </div>
      <p className="ta-preview-note">Preview workspaces open the currently available Cohort pages. Staff-specific records and teaching actions are shown only when supported by your university access.</p>
    </div>
  );
}

function StudentDashboard() {
  const api = useApi();
  const enrollments = useQuery({ queryKey: queryKeys.enrollments, queryFn: () => api.getMyEnrollments() });
  const grades = useQuery({ queryKey: queryKeys.grades, queryFn: () => api.getMyGrades() });

  return (
    <>
      <h1>Dashboard</h1>
      <section>
        <h2>My courses</h2>
        {enrollments.isPending ? <p>Loading…</p> : enrollments.data === undefined ? (
          <p role="alert">{enrollments.error?.message}</p>
        ) : enrollments.data.enrollments.filter((item) => item.status !== "dropped").length === 0 ? (
          <p>You are not registered in any courses yet.</p>
        ) : (
          <ul className="card-list">
            {enrollments.data.enrollments.filter((item) => item.status !== "dropped").map((item) => (
              <li key={item.id}>{`${item.course.code} ${item.course.title} · Section ${item.sectionCode} · ${item.status}`}</li>
            ))}
          </ul>
        )}
      </section>
      <section>
        <h2>Published grades</h2>
        {grades.isPending ? <p>Loading…</p> : grades.data === undefined ? (
          <p role="alert">{grades.error?.message}</p>
        ) : grades.data.grades.length === 0 ? <p>No published grades yet.</p> : (
          <ul className="card-list">
            {grades.data.grades.map((grade) => (
              <li key={grade.id}>{grade.course.code} · {grade.item ?? "Course grade"} · {grade.score} / {grade.maxScore}</li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}

export function DashboardPage() {
  const api = useApi();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });

  if (me.data?.roles.includes("teaching_assistant")) {
    return <TeachingStaffDashboard displayName={me.data.displayName} />;
  }

  return <StudentDashboard />;
}
