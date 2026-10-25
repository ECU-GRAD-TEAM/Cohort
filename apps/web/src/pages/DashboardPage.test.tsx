import type { Enrollment, Grade } from "@cohort/contracts";
import { screen, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, server } from "../../test/server.ts";
import { createFakeAuth, fakeSession, renderApp } from "../../test/render.tsx";

const TERM_ID = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f";

function enrollment(overrides: Partial<Enrollment> & Pick<Enrollment, "id" | "sectionCode" | "course">): Enrollment {
  return {
    sectionId: "d1e2f3a4-b5c6-4d7e-8f9a-0b1c2d3e4f5a",
    termId: TERM_ID,
    status: "enrolled",
    waitlistPosition: null,
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
  item: "Midterm",
  score: 75,
  maxScore: 100,
  publishedAt: "2026-10-01T10:00:00Z",
};
const courseGrade: Grade = {
  id: "f1000000-0000-4000-8000-000000000002",
  offeringId: "a1000000-0000-4000-8000-000000000002",
  course: { code: "MA201", title: "Linear Algebra" },
  item: null,
  score: 88,
  maxScore: 100,
  publishedAt: "2026-10-02T10:00:00Z",
};

const serverError = { error: { code: "internal", message: "Something went wrong. Please try again." } };

function renderDashboard() {
  return renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
}

describe("DashboardPage", () => {
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
});
