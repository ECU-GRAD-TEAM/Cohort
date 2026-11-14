import { useQuery } from "@tanstack/react-query";
import { useState, type FormEvent, type ReactNode } from "react";
import { Link } from "react-router";
import { Icon, type IconName } from "../components/Icons.tsx";
import {
  AcademicYearStepper,
  SegmentedPillSelector,
  type AcademicYearId,
} from "../components/InteractiveSelectors.tsx";
import { useApi } from "../lib/ApiContext.tsx";
import {
  formatCredits,
  formatEnrollmentStatus,
  formatGradeItem,
  formatScore,
  formatSections,
} from "../lib/format.ts";
import { useLanguage } from "../lib/i18n.tsx";
import { queryKeys } from "../lib/queryKeys.ts";
import "../styles/teaching-assistant-dashboard.css";

type TaQueueFilter = "all" | "labs" | "quizzes" | "questions";

function TeachingAssistantDashboard({ displayName }: { displayName: string }) {
  const { t } = useLanguage();
  const firstName = displayName.trim().split(/\s+/)[0] || "there";
  const [selectedYear, setSelectedYear] = useState<AcademicYearId>("all");
  const [queueFilter, setQueueFilter] = useState<TaQueueFilter>("all");

  const workspaces: {
    to: string;
    icon: IconName;
    title: string;
    detail: string;
    metricAction: string;
    shortcutAction: string;
  }[] = [
    {
      to: "/courses",
      icon: "book",
      title: t("Course workspaces", "مساحات المقررات الدراسية"),
      detail: t(
        "Open your course spaces, lab materials, and review the information available to you.",
        "افتح مساحات المقررات، ملفات المعامل، وراجع المحتوى العلمي المتاح لك.",
      ),
      metricAction: t("Open courses", "فتح المقررات"),
      shortcutAction: t("Manage course spaces", "إدارة مساحات المقررات"),
    },
    {
      to: "/assignments",
      icon: "check",
      title: t("Assignments", "التكليفات والتقييمات"),
      detail: t(
        "Find assignment information, lab reports, and the work shared with your courses.",
        "تابع التكليفات وتقارير المعامل والمهام المشتركة مع طلابك.",
      ),
      metricAction: t("Open assignments", "فتح التكليفات"),
      shortcutAction: t("Review student work", "مراجعة تسليمات الطلاب"),
    },
    {
      to: "/schedule",
      icon: "calendar",
      title: t("Teaching schedule", "الجدول التدريسي والمعامل"),
      detail: t(
        "Review your teaching timetable, lab rooms, and upcoming office hour sessions.",
        "راجع جدول السكاشن والمعامل والقاعات والساعات المكتبية القادمة.",
      ),
      metricAction: t("See timetable", "عرض الجدول"),
      shortcutAction: t("Check teaching hours", "مواعيد السكاشن والمعامل"),
    },
    {
      to: "/messages",
      icon: "chat",
      title: t("Student communication", "جروبات التواصل مع الطلاب"),
      detail: t(
        "Continue course-related conversations, share files, or send voice updates to student groups.",
        "تواصل مع جروبات الدفعات، ارفع ملفات السكشن أو أرسل ملاحظات صوتية للطلاب.",
      ),
      metricAction: t("Open messages", "فتح الجروبات"),
      shortcutAction: t("Message student groups", "مراسلة جروبات الطلاب"),
    },
  ];

  const taGroups = [
    {
      code: "CS101 · Lab L1 & L2",
      name: t("Programming I — Section Group", "جروب سكشن البرمجة (1)"),
      members: "142",
      status: t("Active · 4 new questions", "نشط · 4 استفسارات جديدة"),
    },
    {
      code: "CS201 · Data Structures",
      name: t("Algorithms & Lab Announcements", "جروب معمل هياكل البيانات"),
      members: "118",
      status: t("Lab sheet 4 posted", "تم نشر شيت المعمل 4"),
    },
    {
      code: "SE401 · Grad Cohort",
      name: t("Graduation Project Supervision", "جروب إشراف مشاريع التخرج"),
      members: "64",
      status: t("Weekly sprint check-in", "متابعة الأسبوع الحالي"),
    },
  ];

  return (
    <div className="uf-dashboard">
      <div className="uf-heading">
        <div>
          <span className="uf-kicker">
            {t("UNIFLOW / ACADEMIC WORKSPACE", "بوابة الجامعة الذكية · مساحة المعيدين والهيئة المعاونة")}
          </span>
          <h1>{t("Academic Staff Dashboard", "Academic Staff Dashboard")}</h1>
          <p>
            {t(
              "A clear, organized view of your teaching sections, lab groups, and AI assistant tools.",
              "رؤية منظمة وشاملة لسكاشن التدريس، جروبات الطلاب، وأدوات المساعد الذكي.",
            )}
          </p>
        </div>
        <div className="uf-heading-badges">
          <span className="uf-demo">{t("Teaching workspace", "مساحة الهيئة المعاونة")}</span>
          <Link to="/student-assistant" className="uf-ai-pill-link">
            <Icon name="spark" size={14} />
            <span>{t("AI Assistant", "المساعد الذكي")}</span>
          </Link>
        </div>
      </div>

      <section className="uf-hero">
        <div className="uf-hero-copy">
          <span className="uf-kicker">{t("TEACH. CONNECT. INSPIRE.", "تعلّم · تواصل · ألهم")}</span>
          <h2>
            {t("More time for teaching.", "More time for teaching.")}
            <br />
            <em>{t("Everything else, in flow.", "كل أدواتك الأكاديمية في مكان واحد.")}</em>
          </h2>
          <p>
            {t(
              `Welcome back, ${firstName}. Your courses, schedule, AI teaching assistant, and student communication groups are all within reach.`,
              `مرحباً بعودتك، ${firstName}. جميع مقرراتك، جدول السكاشن، المساعد الذكي، وجروبات التواصل مع الطلاب جاهزة بضغطة زر.`,
            )}
          </p>
          <div className="uf-hero-actions">
            <Link className="uf-primary" to="/courses">
              <span>{t("Explore courses", "Explore courses")}</span>
              <Icon name="arrowUpRight" size={14} />
            </Link>
            <Link className="uf-outline" to="/schedule">
              {t("View schedule", "View schedule")}
            </Link>
          </div>
        </div>
        <div className="uf-hero-art" aria-hidden="true">
          <div className="uf-paper uf-paper-back" />
          <div className="uf-paper">
            <span>CS / TA</span>
            <b>
              Aa<span>+</span>
            </b>
            <i />
            <i />
            <i />
            <div className="uf-paper-check">
              <Icon name="check" size={22} />
            </div>
          </div>
        </div>
      </section>

      <AcademicYearStepper
        value={selectedYear}
        onChange={setSelectedYear}
        label={t("Filter teaching cohorts by academic year", "تصفية الفرق الدراسية والسكاشن")}
      />

      <section className="uf-metrics" aria-label="Teaching workspace shortcuts">
        {workspaces.map((item, index) => (
          <Link className="uf-metric" to={item.to} key={item.to}>
            <span className="uf-metric-top">
              <span>{["01", "02", "03", "04"][index]}</span>
              <Icon name="arrowUpRight" size={15} />
            </span>
            <strong>{item.title}</strong>
            <small>{item.metricAction}</small>
          </Link>
        ))}
      </section>

      <div className="uf-columns">
        <div className="uf-stack">
          <section className="uf-panel">
            <div className="uf-panel-head">
              <div>
                <span className="uf-kicker">{t("YOUR PRIORITY", "أولويات المراجعة")}</span>
                <h2>{t("Review queue", "طابور المراجعة والتسليمات")}</h2>
              </div>
              <span className="uf-muted-label">{t("Staff tools", "أدوات المعيد")}</span>
            </div>
            <SegmentedPillSelector
              ariaLabel={t("Filter review queue", "تصفية طابور المراجعة")}
              value={queueFilter}
              onChange={setQueueFilter}
              options={[
                { value: "all", enLabel: "All Items", arLabel: "الكل", badge: "0" },
                { value: "labs", enLabel: "Lab Reports", arLabel: "تقارير المعمل" },
                { value: "quizzes", enLabel: "Quizzes", arLabel: "الكويزات" },
                { value: "questions", enLabel: "Student Q&A", arLabel: "أسئلة الطلاب" },
              ]}
            />
            <div className="uf-empty">
              <span aria-hidden="true">
                <Icon name="check" size={18} />
              </span>
              <p>
                {t(
                  "There are no review items available in this workspace yet.",
                  "لا توجد عناصر معلقة للمراجعة في هذه المساحة حالياً.",
                )}
              </p>
            </div>
          </section>

          <section className="uf-panel">
            <div className="uf-panel-head">
              <div>
                <span className="uf-kicker">{t("COURSE OVERVIEW", "نظرة عامة على المقررات")}</span>
                <h2>{t("Your teaching space", "مساحة التدريس والسكاشن")}</h2>
              </div>
              <Link to="/courses">
                <span>{t("All courses", "كل المقررات")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
            </div>
            <div className="uf-course-grid">
              {workspaces.slice(0, 2).map((item, index) => (
                <Link className="uf-course" to={item.to} key={item.to}>
                  <div className={`uf-course-cover uf-cover-${index}`}>
                    <span>{index === 0 ? "COURSES" : "ASSESSMENTS"}</span>
                    <b>{index === 0 ? "01" : "02"}</b>
                  </div>
                  <div className="uf-course-body">
                    <h3>{item.title}</h3>
                    <p>{item.detail}</p>
                    <span>
                      <span>{item.shortcutAction}</span>
                      <Icon name="arrowUpRight" size={13} />
                    </span>
                  </div>
                </Link>
              ))}
            </div>
          </section>

          <section className="uf-panel">
            <div className="uf-panel-head">
              <div>
                <span className="uf-kicker">
                  {t("COHORT COMMUNICATION", "التواصل المباشر مع الدفعات")}
                </span>
                <h2>{t("Active student groups", "جروبات التواصل مع الطلاب")}</h2>
              </div>
              <Link to="/messages">
                <span>{t("Open chat hub", "فتح مركز المحادثات")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
            </div>
            <div className="uf-group-cards">
              {taGroups.map((group) => (
                <Link to="/messages" key={group.code} className="uf-group-card">
                  <div className="uf-group-card-top">
                    <span className="uf-group-code">{group.code}</span>
                    <span className="uf-group-members">
                      <Icon name="users" size={13} /> {group.members}
                    </span>
                  </div>
                  <strong>{group.name}</strong>
                  <small>{group.status}</small>
                </Link>
              ))}
            </div>
          </section>

          <section className="uf-panel uf-shortcuts">
            <span className="uf-kicker">{t("QUICK ACTIONS", "إجراءات سريعة")}</span>
            <h2>{t("Prepare your next teaching session", "جهّز للسكشن أو المعمل القادم")}</h2>
            <div>
              {workspaces.slice(0, 3).map((item, index) => (
                <Link to={item.to} key={item.to}>
                  <span>{["01", "02", "03"][index]}</span>
                  <b>{item.shortcutAction}</b>
                  <Icon name="arrowUpRight" size={14} />
                </Link>
              ))}
            </div>
          </section>
        </div>

        <div className="uf-stack uf-side-column">
          <section className="uf-panel uf-ai-spotlight">
            <span className="uf-kicker">{t("AI TEACHING ASSISTANT", "المساعد الذكي للمعيد")}</span>
            <h2>{t("Academic AI Copilot", "مساعدك الذكي في التحضير")}</h2>
            <p className="uf-caption">
              {t(
                "Generate lab quizzes, summarize topics, or answer student inquiries with voice & file support.",
                "أنشئ أسئلة كويزات، لخّص شيتات المعمل، أو راجع الملفات والصور بالذكاء الاصطناعي.",
              )}
            </p>
            <Link className="uf-wide uf-wide-brand" to="/student-assistant">
              <Icon name="spark" size={15} />
              <span>{t("Open AI Assistant", "فتح المساعد الذكي")}</span>
              <Icon name="arrowUpRight" size={14} />
            </Link>
          </section>

          <section className="uf-panel uf-planner">
            <div className="uf-panel-head">
              <div>
                <span className="uf-kicker">{t("PLAN YOUR TEACHING", "خطة السكاشن")}</span>
                <h2>{t("Teaching schedule", "الجدول التدريسي")}</h2>
              </div>
              <Link to="/schedule">
                <span>{t("Full calendar", "التقويم الكامل")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
            </div>
            <p className="uf-caption">
              {t(
                "Your timetable and upcoming teaching sessions.",
                "مواعيد السكاشن والمعامل والساعات المكتبية القادمة.",
              )}
            </p>
            <div className="uf-empty uf-compact">
              <span aria-hidden="true">
                <Icon name="clock" size={18} />
              </span>
              <p>
                {t(
                  "Schedule details will appear here when available.",
                  "ستظهر تفاصيل المواعيد هنا فور نشرها.",
                )}
              </p>
            </div>
            <Link className="uf-wide" to="/schedule">
              <span>{t("Open schedule", "فتح الجدول الدراسي")}</span>
              <Icon name="arrowUpRight" size={14} />
            </Link>
          </section>

          <section className="uf-panel uf-lemon">
            <span className="uf-kicker">
              {t("ASSESSMENT & RESOURCES", "التقييم والمصادر العلمية")}
            </span>
            <h2>{t("Everything in one place.", "كل مصادر المقرر في مكان واحد.")}</h2>
            <p>
              {t(
                "Access course information, assignments and learning resources through your teaching workspace.",
                "تصفح بنوك الأسئلة، ملفات المقررات، والتكليفات عبر مساحة العمل الأكاديمية.",
              )}
            </p>
            <Link to="/assignments">{t("Explore assignments", "تصفح التكليفات")}</Link>
            <Link to="/courses">{t("Browse course resources", "استعراض مصادر المقررات")}</Link>
          </section>

          <section className="uf-panel uf-support">
            <span className="uf-tool-mark">?</span>
            <span className="uf-kicker">{t("HERE TO HELP", "الدعم الفني والأكاديمي")}</span>
            <h2>{t("Teaching support", "دعم الهيئة المعاونة")}</h2>
            <p>
              {t(
                "Find support resources or send a request to the university team.",
                "تواصل مع فريق الدعم التقني أو إدارة شؤون المقررات بالجامعة.",
              )}
            </p>
            <Link to="/support">{t("Visit support", "زيارة مركز الدعم")}</Link>
          </section>
        </div>
      </div>
      <p className="uf-footnote">
        {t(
          "Staff-specific records and teaching actions appear only when supported by your university access.",
          "تظهر السجلات الأكاديمية وصلاحيات التدريس وفقاً لصلاحيات حسابك الجامعي.",
        )}
      </p>
    </div>
  );
}

function CoursesSection() {
  const api = useApi();
  const { t } = useLanguage();
  const enrollments = useQuery({
    queryKey: queryKeys.enrollments,
    queryFn: () => api.getMyEnrollments(),
  });
  let content: ReactNode;
  if (enrollments.isPending) content = <p>{t("Loading…", "جاري التحميل…")}</p>;
  else if (enrollments.data === undefined)
    content = <p role="alert">{enrollments.error?.message}</p>;
  else {
    const current = enrollments.data.enrollments.filter(
      (enrollment) => enrollment.status !== "dropped",
    );
    content =
      current.length === 0 ? (
        <div className="uf-empty">
          <span aria-hidden="true">
            <Icon name="book" size={18} />
          </span>
          <p>
            {t(
              "You are not registered in any courses yet.",
              "أنت غير مسجل في أي مقررات دراسية حتى الآن.",
            )}
          </p>
        </div>
      ) : (
        <ul className="card-list uf-student-course-list">
          {current.map((enrollment) => {
            const statusText = formatEnrollmentStatus(
              enrollment.status,
              enrollment.waitlistPosition,
            );
            return (
              <li key={enrollment.id} className="uf-student-course-item">
                <div className="uf-student-course-badges">
                  <span className="uf-course-code-pill">{enrollment.course.code}</span>
                  <span className="uf-course-credits-pill">
                    {formatCredits(enrollment.course.creditHours)}
                  </span>
                  <span className={`uf-status-tag status-${enrollment.status}`}>
                    {statusText}
                  </span>
                </div>
                <p className="uf-enrollment-line">
                  {`${enrollment.course.code} ${enrollment.course.title} · ${formatSections(enrollment.sections)} · ${statusText}`}
                </p>
                <div className="uf-student-course-links">
                  <Link to="/courses">
                    <Icon name="book" size={13} />
                    <span>{t("Course workspace", "مساحة المقرر")}</span>
                  </Link>
                  <Link to="/messages">
                    <Icon name="chat" size={13} />
                    <span>{t("Registered course group", "جروب المقرر المسجل")}</span>
                  </Link>
                </div>
              </li>
            );
          })}
        </ul>
      );
  }
  return (
    <section className="uf-panel">
      <div className="uf-panel-head">
        <div>
          <span className="uf-kicker">{t("PICK UP WHERE YOU LEFT OFF", "استكمل دراستك")}</span>
          <h2>{t("My courses", "مقرراتي الدراسية")}</h2>
        </div>
        <Link to="/courses">
          <span>{t("All courses", "كل المقررات")}</span>
          <Icon name="arrowUpRight" size={13} />
        </Link>
      </div>
      {content}
    </section>
  );
}

function GradesSection() {
  const api = useApi();
  const { t } = useLanguage();
  const grades = useQuery({ queryKey: queryKeys.grades, queryFn: () => api.getMyGrades() });
  const [courseworkScore, setCourseworkScore] = useState("88");
  const [finalExamScore, setFinalExamScore] = useState("90");
  const [projectedResult, setProjectedResult] = useState<string | null>(null);

  function handleCalculateWhatIf(event: FormEvent) {
    event.preventDefault();
    const cw = Math.min(100, Math.max(0, Number(courseworkScore) || 0));
    const fin = Math.min(100, Math.max(0, Number(finalExamScore) || 0));
    const projected = (cw * 0.6 + fin * 0.4).toFixed(1);
    setProjectedResult(`${projected}% projected overall`);
  }

  let content: ReactNode;
  if (grades.isPending) content = <p>{t("Loading…", "جاري التحميل…")}</p>;
  else if (grades.data === undefined) content = <p role="alert">{grades.error?.message}</p>;
  else if (grades.data.grades.length === 0)
    content = (
      <div className="uf-empty">
        <span aria-hidden="true">
          <Icon name="chart" size={18} />
        </span>
        <p>{t("No published grades yet.", "لا توجد درجات معلنة حتى الآن.")}</p>
      </div>
    );
  else
    content = (
      <div className="uf-table-wrap">
        <table>
          <thead>
            <tr>
              <th scope="col">{t("Course", "المقرر")}</th>
              <th scope="col">{t("Item", "بند التقييم")}</th>
              <th scope="col">{t("Score", "الدرجة")}</th>
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
      </div>
    );

  return (
    <section className="uf-panel">
      <div className="uf-panel-head">
        <div>
          <span className="uf-kicker">
            {t("GRADES & ACADEMIC STANDING", "الأداء الأكاديمي والمعدل التراكمي")}
          </span>
          <h2>{t("Published grades", "الدرجات المعلنة")}</h2>
        </div>
        <span className="uf-muted-label">
          {t("Cumulative GPA: 3.61 · 78 / 120 Credits", "المعدل التراكمي: 3.61 · 78 / 120 ساعة")}
        </span>
      </div>
      {content}

      {/* UniFlow What-If Grade Calculator */}
      <div className="uf-whatif-box">
        <div className="uf-whatif-head">
          <Icon name="chart" size={16} />
          <div>
            <h3>{t("What-if grade calculator", "حاسبة التقدير المتوقع")}</h3>
            <small>
              {t(
                "Estimate your overall course result (Coursework 60% · Final exam 40%). Scenario only.",
                "احسب نتيجتك المتوقعة للمقرر (أعمال السنة 60% · الامتحان النهائي 40%).",
              )}
            </small>
          </div>
        </div>
        <form className="uf-whatif-form" onSubmit={handleCalculateWhatIf}>
          <label>
            <span>{t("Coursework (%)", "أعمال السنة (%)")}</span>
            <input
              type="number"
              min={0}
              max={100}
              value={courseworkScore}
              onChange={(e) => setCourseworkScore(e.target.value)}
            />
          </label>
          <label>
            <span>{t("Expected final (%)", "الامتحان النهائي (%)")}</span>
            <input
              type="number"
              min={0}
              max={100}
              value={finalExamScore}
              onChange={(e) => setFinalExamScore(e.target.value)}
            />
          </label>
          <button type="submit" className="button-secondary uf-whatif-btn">
            {t("Calculate result", "احسب النتيجة")}
          </button>
        </form>
        {projectedResult && <p className="uf-whatif-result">{projectedResult}</p>}
      </div>
    </section>
  );
}

function StudentDashboard({ displayName }: { displayName: string }) {
  const { t } = useLanguage();
  const firstName = displayName.trim().split(/\s+/)[0] || "Student";
  const [selectedYear, setSelectedYear] = useState<AcademicYearId>("year-4");

  // Core UniFlow Student Dashboard Stat Cards (GPA, Attendance, Active Courses, Upcoming Tasks)
  const uniflowStats: { value: string; label: string; sub: string; icon: IconName }[] = [
    {
      value: "3.68",
      label: t("Current GPA", "المعدل الفصلي الحالي"),
      sub: t("Cumulative 3.61 · Good standing", "التراكمي 3.61 · تقدير جيد جداً"),
      icon: "chart",
    },
    {
      value: "94%",
      label: t("Attendance", "نسبة الحضور"),
      sub: t("Across lectures & lab sections", "في المحاضرات والمعامل"),
      icon: "users",
    },
    {
      value: "6",
      label: t("Active courses", "المقررات النشطة"),
      sub: t("18 credit hours · Fall 2026", "18 ساعة معتمدة · خريف 2026"),
      icon: "book",
    },
    {
      value: "3",
      label: t("Upcoming tasks", "التكليفات القادمة"),
      sub: t("Due this week", "مستحقة هذا الأسبوع"),
      icon: "check",
    },
  ];

  // UniFlow Quick Action Shortcuts
  const quickActions: { to: string; label: string; icon: IconName }[] = [
    { to: "/assignments", label: t("Assignments", "التكليفات"), icon: "check" },
    { to: "/register", label: t("Registration", "التسجيل"), icon: "file" },
    { to: "/schedule", label: t("Schedule", "الجدول الدراسي"), icon: "calendar" },
    { to: "/student-assistant", label: t("AI Assistant", "المساعد الذكي"), icon: "spark" },
  ];

  // UniFlow Today's Schedule Timeline
  const todayTimeline = [
    {
      start: "09:00",
      end: "10:15",
      course: "Data Structures",
      room: "Engineering Hall 101",
      next: true,
    },
    {
      start: "11:00",
      end: "12:15",
      course: "Computer Networks",
      room: "Science Building 220",
      next: false,
    },
    {
      start: "13:30",
      end: "14:45",
      course: "Database Systems",
      room: "Engineering Hall 315",
      next: false,
    },
  ];

  // UniFlow On Your Radar Deadlines
  const radarDeadlines = [
    {
      title: "Binary search tree implementation",
      course: "Data Structures",
      due: "Due Oct 29 · 11:59 PM",
    },
    {
      title: "Database normalization report",
      course: "Database Systems",
      due: "Due Oct 30 · 11:59 PM",
    },
    {
      title: "Network protocol analysis",
      course: "Computer Networks",
      due: "Due Nov 02 · 11:59 PM",
    },
  ];

  return (
    <div className="uf-dashboard uf-student-dashboard">
      <div className="uf-heading">
        <div>
          <span className="uf-kicker">
            {t("UNIFLOW / STUDENT WORKSPACE", "بوابة الجامعة الذكية · مساحة الطالب الأكاديمية")}
          </span>
          <h1>{t("Dashboard", "لوحة تحكم الطالب")}</h1>
          <p>
            {t(
              `Welcome back, ${firstName}. Your university, in one place — a fresh day and a world of possibilities.`,
              `أهلاً بعودتك يا ${firstName}. جامعتك في مكان واحد — تابع معدلك، مقرراتك، وجدولك اليومي.`,
            )}
          </p>
        </div>
        <div className="uf-heading-badges">
          <span className="uf-demo">{t("Fall semester 2026 · Week 7", "فصل الخريف 2026 · الأسبوع 7")}</span>
          <Link to="/profile" className="uf-demo">
            <Icon name="user" size={13} />
            <span>{t("Academic Profile", "الملف الأكاديمي")}</span>
          </Link>
        </div>
      </div>

      {/* UniFlow Student Hero with Orbit */}
      <section className="uf-hero uf-student-hero">
        <div className="uf-hero-copy">
          <span className="uf-kicker">
            {t("YOUR NEXT CHAPTER STARTS HERE", "خطواتك الأكاديمية القادمة")}
          </span>
          <h2>
            {t("Small steps today.", "خطوات صغيرة اليوم.")}
            <br />
            <em>{t("Big possibilities tomorrow.", "آفاق واسعة غداً.")}</em>
          </h2>
          <p>
            {t(
              "You have 3 classes today. Review your schedule, track your GPA, or ask the AI Assistant.",
              "لديك 3 محاضرات اليوم. راجع جدولك الدراسي، تابع معدلك التراكمي، أو استعن بالمساعد الذكي.",
            )}
          </p>
          <div className="uf-hero-actions">
            <Link className="uf-primary" to="/schedule">
              <span>{t("View my schedule", "عرض جدولي الدراسي")}</span>
              <Icon name="arrowUpRight" size={14} />
            </Link>
            <Link className="uf-outline" to="/student-assistant">
              <Icon name="spark" size={14} />
              <span>{t("AI Assistant", "المساعد الذكي")}</span>
            </Link>
            <Link className="uf-outline" to="/messages">
              <Icon name="chat" size={14} />
              <span>{t("Course Groups", "جروبات المقررات")}</span>
            </Link>
          </div>
        </div>
        <div className="uf-orbit" aria-hidden="true">
          <span className="uf-planet" />
          <span className="uf-planet two" />
        </div>
      </section>

      {/* UniFlow Quick Actions Bar */}
      <div className="uf-quickactions-row" role="navigation" aria-label={t("Student quick actions", "إجراءات الطالب السريعة")}>
        {quickActions.map((item) => (
          <Link key={item.to} to={item.to} className="uf-quickaction-pill">
            <Icon name={item.icon} size={16} />
            <span>{item.label}</span>
          </Link>
        ))}
      </div>

      {/* Core UniFlow 4 Stat Cards (GPA, Attendance, Active Courses, Upcoming Tasks) */}
      <section className="uf-stats-grid" aria-label={t("Academic overview metrics", "مؤشرات الأداء الأكاديمي")}>
        {uniflowStats.map((stat) => (
          <div key={stat.label} className="uf-stat-card">
            <span className="uf-stat-ico">
              <Icon name={stat.icon} size={20} />
            </span>
            <div className="uf-stat-body">
              <strong>{stat.value}</strong>
              <b>{stat.label}</b>
              <small>{stat.sub}</small>
            </div>
          </div>
        ))}
      </section>

      <AcademicYearStepper
        value={selectedYear}
        onChange={setSelectedYear}
        label={t("Select your academic year", "اختر الفرقة الدراسية")}
      />

      <div className="uf-columns">
        <div className="uf-stack">
          <CoursesSection />
          <GradesSection />

          {/* UniFlow Campus Innovation Banner */}
          <section className="uf-panel uf-campus-announcement">
            <span className="uf-announcement-icon" aria-hidden="true">
              <Icon name="map" size={20} />
            </span>
            <div className="uf-announcement-copy">
              <b>{t("Something good is happening on campus.", "فعاليات مميزة في الحرم الجامعي.")}</b>
              <p>
                {t(
                  "Innovation Week is almost here. Meet, build, and find your people across student workshops.",
                  "أسبوع الابتكار الجامعي يقترب. شارك في ورش العمل الطلابية والمشاريع التطبيقية.",
                )}
              </p>
            </div>
            <Link to="/campus" className="uf-announcement-link">
              <span>{t("Explore events", "استكشف الفعاليات")}</span>
              <Icon name="arrowUpRight" size={14} />
            </Link>
          </section>
        </div>

        <div className="uf-stack uf-side-column">
          {/* UniFlow Today's Schedule Panel */}
          <section className="uf-panel">
            <div className="uf-panel-head">
              <div>
                <span className="uf-kicker">{t("DAILY TIMELINE", "جدول محاضرات اليوم")}</span>
                <h2>{t("Today's schedule", "جدول اليوم")}</h2>
              </div>
              <Link to="/schedule">
                <span>{t("View all", "عرض الكل")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
            </div>
            <div className="uf-timeline">
              {todayTimeline.map((slot) => (
                <div key={slot.start + slot.course} className="uf-timeline-event">
                  <div className="uf-timeline-time">
                    <strong>{slot.start}</strong>
                    <small>{slot.end}</small>
                  </div>
                  <div className="uf-timeline-body">
                    <b>{slot.course}</b>
                    <small>
                      <Icon name="map" size={12} /> {slot.room}
                    </small>
                    {slot.next && (
                      <span className="uf-next-class-badge">
                        {t("Next class", "المحاضرة القادمة")}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </section>

          {/* UniFlow AI Assistant Card */}
          <section className="uf-panel uf-lemon">
            <div className="uf-spark-badge" aria-hidden="true">
              <Icon name="spark" size={20} />
            </div>
            <span className="uf-kicker">{t("AI STUDY COMPANION", "المساعد الدراسي الذكي")}</span>
            <h2>{t("A little help goes a long way.", "مساعدة ذكية في كل خطوة.")}</h2>
            <p>
              {t(
                "Your courses, your next deadline, your next big question. Start here.",
                "استفسر عن مقرراتك، المواعيد النهائية، أو اطلب شرحاً مبسطاً لأي موضوع دراسي.",
              )}
            </p>
            <Link className="uf-wide uf-wide-brand" to="/student-assistant">
              <Icon name="spark" size={15} />
              <span>{t("Ask AI Assistant", "اسأل المساعد الذكي")}</span>
              <Icon name="arrowUpRight" size={14} />
            </Link>
          </section>

          {/* UniFlow On Your Radar Deadlines Panel */}
          <section className="uf-panel">
            <div className="uf-panel-head">
              <div>
                <span className="uf-kicker">{t("UPCOMING DEADLINES", "مواعيد التسليم")}</span>
                <h2>{t("On your radar", "تحت المتابعة")}</h2>
              </div>
              <Link to="/assignments">
                <span>{t("View all", "عرض الكل")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
            </div>
            <div className="uf-radar-list">
              {radarDeadlines.map((task) => (
                <div key={task.title} className="uf-radar-row">
                  <span className="uf-radar-ico" aria-hidden="true">
                    <Icon name="file" size={15} />
                  </span>
                  <div>
                    <b>{task.title}</b>
                    <small>{`${task.course} · ${task.due}`}</small>
                  </div>
                </div>
              ))}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}

export function DashboardPage() {
  const api = useApi();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });
  if (me.data?.roles.includes("teaching_assistant")) {
    return <TeachingAssistantDashboard displayName={me.data.displayName} />;
  }
  return <StudentDashboard displayName={me.data?.displayName ?? "Student"} />;
}
