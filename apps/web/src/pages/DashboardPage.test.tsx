import type { Enrollment, Grade } from "@cohort/contracts";
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, defaultMe, server } from "../../test/server.ts";
import { createFakeAuth, fakeSession, renderApp } from "../../test/render.tsx";

const TERM_ID = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f";

/** An enrolment in one section, `sectionCode`, or in none when it is null. */
function enrollment({
  sectionCode,
  ...overrides
}: Partial<Enrollment> & Pick<Enrollment, "id" | "course"> & { sectionCode: string | null }): Enrollment {
  return {
    termId: TERM_ID,
    status: "enrolled",
    waitlistPosition: null,
    sections: sectionCode === null ? [] : [{ id: "d1e2f3a4-b5c6-4d7e-8f9a-0b1c2d3e4f5a", code: sectionCode }],
    ...overrides,
  };
}

const cs101 = enrollment({
  id: "e1000000-0000-4000-8000-000000000001",
  sectionCode: "L1",
  course: { code: "CS101", title: "Programming I", creditHours: 3 },
});
const ma201 = enrollment({
  id: "e1000000-0000-4000-8000-000000000002",
  sectionCode: "L2",
  status: "waitlisted",
  waitlistPosition: 2,
  course: { code: "MA201", title: "Linear Algebra", creditHours: 3.5 },
});
const cs201 = enrollment({
  id: "e1000000-0000-4000-8000-000000000003",
  sectionCode: "L1",
  status: "dropped",
  course: { code: "CS201", title: "Data Structures", creditHours: 3 },
});

const midterm: Grade = {
  id: "f1000000-0000-4000-8000-000000000001",
  offeringId: "a1000000-0000-4000-8000-000000000001",
  course: { code: "CS101", title: "Programming I" },
  componentId: "b1000000-0000-4000-8000-000000000001",
  item: "Midterm",
  score: 75,
  maxScore: 100,
  publishedAt: "2026-10-01T10:00:00Z",
};
const courseGrade: Grade = {
  id: "f1000000-0000-4000-8000-000000000002",
  offeringId: "a1000000-0000-4000-8000-000000000002",
  course: { code: "MA201", title: "Linear Algebra" },
  componentId: null,
  item: null,
  score: 88,
  maxScore: 100,
  publishedAt: "2026-10-02T10:00:00Z",
};
// Graded on a component the student cannot see yet, so the API knows its id but not its name.
const hiddenComponentGrade: Grade = {
  id: "f1000000-0000-4000-8000-000000000003",
  offeringId: "a1000000-0000-4000-8000-000000000001",
  course: { code: "CS101", title: "Programming I" },
  componentId: "b1000000-0000-4000-8000-000000000002",
  item: null,
  score: 64,
  maxScore: 100,
  publishedAt: "2026-10-03T10:00:00Z",
};

const serverError = { error: { code: "internal", message: "Something went wrong. Please try again." } };

function renderDashboard() {
  return renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
}

describe("DashboardPage", () => {
  it("shows the teaching workspace to a teaching assistant", async () => {
    server.use(
      http.get(`${API}/me`, () => HttpResponse.json({ ...defaultMe, userType: "staff", roles: ["teaching_assistant"], displayName: "Mona Hassan" })),
    );
    renderDashboard();
    expect(await screen.findByRole("heading", { name: "Academic Staff Dashboard" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: /More time for teaching/ })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Explore courses/ })).toHaveAttribute("href", "/courses");
    expect(screen.getByRole("link", { name: /View schedule/ })).toHaveAttribute("href", "/schedule");
    expect(screen.getByRole("link", { name: /Open assignments/ })).toHaveAttribute("href", "/assignments");
    expect(screen.queryByRole("heading", { name: "Published grades" })).not.toBeInTheDocument();
  });

  it("lists current courses and published grades", async () => {
    server.use(
      http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [cs101, ma201, cs201] })),
      http.get(`${API}/me/grades`, () => HttpResponse.json({ grades: [midterm, courseGrade] })),
    );
    renderDashboard();
    expect(await screen.findByText("CS101 Programming I · Section L1 · Enrolled")).toBeInTheDocument();
    expect(screen.getByText("MA201 Linear Algebra · Section L2 · Waitlisted (position 2)")).toBeInTheDocument();
    expect(screen.queryByText(/CS201/)).not.toBeInTheDocument();
    const rows = within(await screen.findByRole("table")).getAllByRole("row");
    expect(rows[0]).toHaveTextContent("CourseItemScore");
    expect(rows[1]).toHaveTextContent("CS101Midterm75 / 100");
    expect(rows[2]).toHaveTextContent("Course grade88 / 100");
  });

  it("calls a grade whose component is not visible yet a graded item, not the course grade", async () => {
    server.use(
      http.get(`${API}/me/grades`, () => HttpResponse.json({ grades: [midterm, hiddenComponentGrade, courseGrade] })),
    );
    renderDashboard();
    const rows = within(await screen.findByRole("table")).getAllByRole("row");
    expect(rows[1]).toHaveTextContent("CS101Midterm75 / 100");
    expect(rows[2]).toHaveTextContent("CS101Graded item64 / 100");
    expect(rows[3]).toHaveTextContent("MA201Course grade88 / 100");
  });

  it("lists enrolments in every status except dropped", async () => {
    const withStatus = (status: Enrollment["status"], code: string) =>
      enrollment({
        id: `e2000000-0000-4000-8000-0000000000${code.slice(-2)}`,
        sectionCode: "L1",
        status,
        course: { code, title: "Course", creditHours: 3 },
      });
    server.use(
      http.get(`${API}/me/enrollments`, () =>
        HttpResponse.json({
          enrollments: [
            withStatus("withdrawn", "XX11"),
            withStatus("completed", "XX12"),
            withStatus("failed", "XX13"),
            withStatus("incomplete", "XX14"),
            withStatus("dropped", "XX15"),
          ],
        }),
      ),
    );
    renderDashboard();
    expect(await screen.findByText("XX11 Course · Section L1 · Withdrawn")).toBeInTheDocument();
    expect(screen.getByText("XX12 Course · Section L1 · Completed")).toBeInTheDocument();
    expect(screen.getByText("XX13 Course · Section L1 · Failed")).toBeInTheDocument();
    expect(screen.getByText("XX14 Course · Section L1 · Incomplete")).toBeInTheDocument();
    expect(screen.queryByText(/XX15/)).not.toBeInTheDocument();
  });

  it("says when there is nothing yet", async () => {
    server.use(
      http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [] })),
      http.get(`${API}/me/grades`, () => HttpResponse.json({ grades: [] })),
    );
    renderDashboard();
    expect(await screen.findByText("You are not registered in any courses yet.")).toBeInTheDocument();
    expect(await screen.findByText("No published grades yet.")).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("says there are no courses when every enrolment was dropped", async () => {
    server.use(http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [cs201] })));
    renderDashboard();
    expect(await screen.findByText("You are not registered in any courses yet.")).toBeInTheDocument();
  });

  it("shows each section's loading state until its data arrives", async () => {
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get(`${API}/me/enrollments`, async () => {
        await gate;
        return HttpResponse.json({ enrollments: [cs101] });
      }),
      http.get(`${API}/me/grades`, async () => {
        await gate;
        return HttpResponse.json({ grades: [midterm] });
      }),
    );
    renderDashboard();
    const courses = (await screen.findByRole("heading", { name: "My courses" })).closest("section");
    const grades = screen.getByRole("heading", { name: "Published grades" }).closest("section");
    expect(courses).toHaveTextContent("Loading…");
    expect(grades).toHaveTextContent("Loading…");
    release();
    expect(await screen.findByText("CS101 Programming I · Section L1 · Enrolled")).toBeInTheDocument();
    expect(await screen.findByRole("table")).toBeInTheDocument();
    expect(screen.queryByText("Loading…")).not.toBeInTheDocument();
  });

  it("keeps the grades when the courses fail to load", async () => {
    server.use(
      http.get(`${API}/me/enrollments`, () => HttpResponse.json(serverError, { status: 500 })),
      http.get(`${API}/me/grades`, () => HttpResponse.json({ grades: [midterm] })),
    );
    renderDashboard();
    expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong. Please try again.");
    const rows = within(await screen.findByRole("table")).getAllByRole("row");
    expect(rows[1]).toHaveTextContent("CS101Midterm75 / 100");
    expect(screen.getAllByRole("alert")).toHaveLength(1);
  });

  it("keeps the courses when the grades fail to load", async () => {
    server.use(
      http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [cs101] })),
      http.get(`${API}/me/grades`, () => HttpResponse.json(serverError, { status: 500 })),
    );
    renderDashboard();
    expect(await screen.findByText("CS101 Programming I · Section L1 · Enrolled")).toBeInTheDocument();
    expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong. Please try again.");
    expect(screen.getAllByRole("alert")).toHaveLength(1);
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("toggles between English and Arabic with one click and updates layout direction", async () => {
    renderDashboard();
    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();

    const langToggle = screen.getByRole("button", { name: "Switch language to Arabic" });
    await userEvent.click(langToggle);

    expect(await screen.findByRole("heading", { name: "لوحة تحكم الطالب" })).toBeInTheDocument();
    expect(document.documentElement.dir).toBe("rtl");
    expect(document.documentElement.lang).toBe("ar");

    await userEvent.click(screen.getByRole("button", { name: "Switch language to English" }));
    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
    expect(document.documentElement.dir).toBe("ltr");
  });

  it("lets students switch academic years using the interactive card stepper and open quick chat & voice recording", async () => {
    renderDashboard();
    await screen.findByRole("heading", { name: "Dashboard" });

    // Verify UniFlow GPA display and What-If Grade Calculator
    expect(screen.getAllByText("3.68").length).toBeGreaterThan(0);
    const courseworkInput = screen.getByLabelText("Coursework (%)");
    await userEvent.clear(courseworkInput);
    await userEvent.type(courseworkInput, "90");
    await userEvent.click(screen.getByRole("button", { name: "Calculate result" }));
    expect(screen.getByText("90.0% projected overall")).toBeInTheDocument();

    const yearSelector = screen.getByRole("group", { name: "Select your academic year" });
    const year2Button = within(yearSelector).getByRole("button", { name: /Level 2 · Sophomore/ });
    expect(year2Button).toHaveAttribute("aria-pressed", "false");
    await userEvent.click(year2Button);
    expect(year2Button).toHaveAttribute("aria-pressed", "true");

    // Verify floating button is renamed to "AI Assistant"
    expect(screen.getByRole("button", { name: "AI Assistant" })).toBeInTheDocument();

    // Open quick Communication Groups drawer from the floating dock
    await userEvent.click(screen.getByRole("button", { name: /Course Groups/ }));
    const groupsDrawer = await screen.findByRole("region", { name: "Quick Communication Groups" });
    expect(groupsDrawer).toBeInTheDocument();

    // Record and attach a voice note inside the group chat drawer
    await userEvent.click(within(groupsDrawer).getByRole("button", { name: "Record voice" }));
    await userEvent.click(within(groupsDrawer).getByRole("button", { name: /Attach voice/ }));
    await userEvent.click(within(groupsDrawer).getByRole("button", { name: "Post" }));
    expect(within(groupsDrawer).getByText(/Voice Note/)).toBeInTheDocument();
  });

  it("opens the read-only Profile page from the header profile icon with mailto academic advisor link", async () => {
    renderDashboard();
    await screen.findByRole("heading", { name: "Dashboard" });

    const profileTrigger = screen.getByRole("link", { name: "Open academic profile" });
    await userEvent.click(profileTrigger);

    expect(await screen.findByRole("heading", { level: 1, name: "Academic Profile" })).toBeInTheDocument();
    expect(screen.getByText("Personal Email")).toBeInTheDocument();
    expect(screen.getByText("Academic Year")).toBeInTheDocument();
    expect(screen.getByText("Contact Information")).toBeInTheDocument();
    expect(screen.getByText("+20 100 245 8910")).toBeInTheDocument();

    const advisorLink = screen.getByRole("link", { name: /dr\.leila\.hassan@ecu\.edu\.eg/i });
    expect(advisorLink).toHaveAttribute("href", expect.stringMatching(/^mailto:dr\.leila\.hassan@ecu\.edu\.eg/));
  });

  it("supports creating, switching, and deleting conversations plus Resend and Edit actions on AI Assistant", async () => {
    server.use(
      http.post(`${API}/student-ai/chat`, () =>
        HttpResponse.json({
          answer: "CS305 requires Data Structures (CS201) and Discrete Math.",
          language: "en",
          provider: "test",
          model: "test-model",
          latency_ms: 42,
          sources: [],
          limitations: [],
        }),
      ),
    );
    renderApp({ route: "/student-assistant", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { level: 1, name: "AI Assistant" })).toBeInTheDocument();

    // Create a new conversation
    await userEvent.click(screen.getByRole("button", { name: /New chat/i }));
    expect(screen.getByText(/New conversation 3/i)).toBeInTheDocument();

    // Send a message using Enter key
    const input = screen.getByLabelText("Message");
    await userEvent.type(input, "What are the prerequisites for CS305?{Enter}");

    expect(await screen.findByText("What are the prerequisites for CS305?")).toBeInTheDocument();
    expect(
      await screen.findByText("CS305 requires Data Structures (CS201) and Discrete Math."),
    ).toBeInTheDocument();

    // Verify Resend button is present on the sent message
    expect(screen.getByRole("button", { name: "Resend message" })).toBeInTheDocument();

    // Edit the sent message
    const editBtn = screen.getByRole("button", { name: "Edit message" });
    await userEvent.click(editBtn);
    expect(screen.getByLabelText("Edit message text")).toHaveValue("What are the prerequisites for CS305?");
    await userEvent.click(screen.getByRole("button", { name: "Save" }));

    // Delete a conversation
    const deleteBtns = screen.getAllByRole("button", { name: /Delete conversation/i });
    await userEvent.click(deleteBtns[0]!);
  });

  it("restricts Course Groups to registered courses and supports own-message edit/delete, WhatsApp reactions, and polls", async () => {
    renderApp({ route: "/messages", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { level: 1, name: "Messages" })).toBeInTheDocument();

    // Verify registered courses access notice is present and year stepper is not present
    expect(
      screen.getByText(/You can only view and communicate in groups for your strictly registered courses/i),
    ).toBeInTheDocument();
    expect(screen.queryByRole("group", { name: /Academic year/i })).not.toBeInTheDocument();

    // React to a message with a WhatsApp emoji reaction
    const heartButtons = screen.getAllByRole("button", { name: "React with Heart" });
    await userEvent.click(heartButtons[0]!);

    // Open "+" attachment menu and create a poll
    await userEvent.click(screen.getByRole("button", { name: "More attachment options" }));
    await userEvent.click(screen.getByRole("menuitem", { name: "Create poll" }));
    await userEvent.type(screen.getByLabelText("Poll question"), "Best day for lab review?");
    await userEvent.type(screen.getByLabelText("Poll option 1"), "Sunday");
    await userEvent.type(screen.getByLabelText("Poll option 2"), "Tuesday");
    await userEvent.click(screen.getByRole("button", { name: "Attach Poll" }));

    // Send the poll
    await userEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(await screen.findByText("Best day for lab review?")).toBeInTheDocument();

    // User's own message has Edit and Delete buttons
    expect(screen.getAllByRole("button", { name: "Edit own message" }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole("button", { name: "Delete own message" }).length).toBeGreaterThan(0);
  });
});
