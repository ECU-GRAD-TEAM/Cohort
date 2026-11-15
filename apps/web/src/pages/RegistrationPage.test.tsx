import type { CatalogueSection, Enrollment, Term } from "@cohort/contracts";
import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it } from "vitest";
import { API, server } from "../../test/server.ts";
import { createFakeAuth, fakeSession, renderApp } from "../../test/render.tsx";

const openTermId = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f";
const closedTermId = "c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e60";
const cs101 = "d1000000-0000-4000-8000-000000000101";
const cs201 = "d1000000-0000-4000-8000-000000000201";
const enrollmentId = "e1000000-0000-4000-8000-000000000001";

// The page picks its default term against the real clock, so the windows are far either side of it.
const openTerm: Term = {
  id: openTermId,
  code: "F26",
  name: "Fall 2026",
  startsOn: "2026-09-01",
  endsOn: "2027-01-31",
  registrationOpensAt: "2000-01-01T00:00:00Z",
  registrationClosesAt: "2100-01-01T00:00:00Z",
  addDropEndsAt: null,
};
const closedTerm: Term = {
  ...openTerm,
  id: closedTermId,
  code: "S26",
  name: "Spring 2026",
  registrationOpensAt: "2001-01-01T00:00:00Z",
  registrationClosesAt: "2001-02-01T00:00:00Z",
};

const cs101Section: CatalogueSection = {
  id: cs101,
  code: "L1",
  kind: "lecture",
  capacity: 30,
  course: { id: "b1000000-0000-4000-8000-000000000101", code: "CS101", title: "Programming I", creditHours: 3.5 },
  meetings: [{ weekday: 7, startsAt: "09:05", endsAt: "10:30", room: "101" }],
};
const cs201Section: CatalogueSection = {
  id: cs201,
  code: "L1",
  kind: "lecture",
  capacity: null,
  course: { id: "b1000000-0000-4000-8000-000000000201", code: "CS201", title: "Data Structures", creditHours: 3 },
  meetings: [
    { weekday: 1, startsAt: "09:00", endsAt: "10:30", room: "B12" },
    { weekday: 3, startsAt: "09:00", endsAt: "10:30", room: null },
  ],
};
const sections = [cs101Section, cs201Section];

const serverError = { error: { code: "internal", message: "Something went wrong. Please try again." } };

function enrollmentIn(section: CatalogueSection, overrides: Partial<Enrollment> = {}): Enrollment {
  return {
    id: enrollmentId,
    termId: openTermId,
    status: "enrolled",
    waitlistPosition: null,
    course: { code: section.course.code, title: section.course.title, creditHours: section.course.creditHours },
    sections: [{ id: section.id, code: section.code }],
    ...overrides,
  };
}

/** A promise a test settles itself, so a request can be held open and then released. */
function gate() {
  let open!: () => void;
  const opened = new Promise<void>((resolve) => {
    open = resolve;
  });
  return { opened, open };
}

beforeEach(() => {
  server.use(
    http.get(`${API}/terms`, () => HttpResponse.json({ terms: [openTerm] })),
    http.get(`${API}/terms/:termId/sections`, () => HttpResponse.json({ sections })),
    http.get(`${API}/me/enrollments`, () => HttpResponse.json({ enrollments: [] })),
  );
});

/** The list item of a section, found by its course code. */
function rowOf(courseCode: string) {
  return screen.getByText(new RegExp(`^${courseCode} `)).closest("li")!;
}

function renderRegistration() {
  return renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
}

/** Waits for the page itself (not the shell's own "Loading…"), so the next "Loading…" is the page's. */
async function pageHeading() {
  return screen.findByRole("heading", { name: "Course registration" });
}

describe("RegistrationPage", () => {
  describe("sections", () => {
    it("lists sections with credits and meetings", async () => {
      renderRegistration();
      expect(await screen.findByText("CS101 Programming I · Section L1 · 3.5 credits")).toBeInTheDocument();
      expect(screen.getByText("Sun 09:05–10:30 · Room 101")).toBeInTheDocument();
      expect(screen.getByText("CS201 Data Structures · Section L1 · 3 credits")).toBeInTheDocument();
      expect(screen.getByText("Mon 09:00–10:30 · Room B12")).toBeInTheDocument();
      expect(screen.getByText("Wed 09:00–10:30")).toBeInTheDocument();
    });

    it("marks the sections the student is assigned to, enrolled or waitlisted, and no others", async () => {
      server.use(
        http.get(`${API}/me/enrollments`, () =>
          HttpResponse.json({
            enrollments: [
              enrollmentIn(cs101Section, { status: "waitlisted", waitlistPosition: 2 }),
              enrollmentIn(cs201Section, { status: "dropped" }),
            ],
          }),
        ),
      );
      renderRegistration();
      await screen.findByText("CS101 Programming I · Section L1 · 3.5 credits");
      expect(within(rowOf("CS101")).getByText("Your section")).toBeInTheDocument();
      expect(within(rowOf("CS201")).queryByText("Your section")).not.toBeInTheDocument();
    });

    it("explains that the registrar enrols students, and offers no register or drop buttons", async () => {
      renderRegistration();
      expect(await screen.findByText(/Your registrar enrols you in courses and assigns your class meetings/)).toBeInTheDocument();
      await screen.findByText("CS101 Programming I · Section L1 · 3.5 credits");
      expect(within(screen.getByRole("main")).queryByRole("button")).toBeNull();
    });

    it("says when a term has no published sections", async () => {
      server.use(http.get(`${API}/terms/:termId/sections`, () => HttpResponse.json({ sections: [] })));
      renderRegistration();
      expect(await screen.findByText("No sections are published for this term yet.")).toBeInTheDocument();
    });
  });

  describe("terms", () => {
    it("starts on the term whose registration window is open and loads another term's sections on change", async () => {
      server.use(
        http.get(`${API}/terms`, () => HttpResponse.json({ terms: [closedTerm, openTerm] })),
        http.get(`${API}/terms/:termId/sections`, ({ params }) =>
          HttpResponse.json({ sections: params.termId === openTermId ? [cs101Section] : [cs201Section] }),
        ),
      );
      renderRegistration();
      const select = await screen.findByRole("combobox", { name: "Term" });
      expect(within(select).getAllByRole("option").map((option) => option.textContent)).toEqual([
        "Spring 2026",
        "Fall 2026",
      ]);
      expect(select).toHaveValue(openTermId);
      expect(await screen.findByText(/^CS101 Programming I/)).toBeInTheDocument();

      await userEvent.selectOptions(select, "Spring 2026");
      expect(await screen.findByText(/^CS201 Data Structures/)).toBeInTheDocument();
      expect(screen.queryByText(/^CS101 Programming I/)).not.toBeInTheDocument();
      expect(select).toHaveValue(closedTermId);
    });

    it("starts on the first term when none has an open window", async () => {
      server.use(
        http.get(`${API}/terms`, () =>
          HttpResponse.json({ terms: [closedTerm, { ...closedTerm, id: openTermId, name: "Older" }] }),
        ),
      );
      renderRegistration();
      expect(await screen.findByRole("combobox", { name: "Term" })).toHaveValue(closedTermId);
    });

    it("says when there are no terms", async () => {
      server.use(http.get(`${API}/terms`, () => HttpResponse.json({ terms: [] })));
      renderRegistration();
      expect(await screen.findByText("No terms are available.")).toBeInTheDocument();
      expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
    });
  });

  describe("loading and failures", () => {
    it("shows Loading… until the terms arrive, and not the empty state", async () => {
      const terms = gate();
      server.use(
        http.get(`${API}/terms`, async () => {
          await terms.opened;
          return HttpResponse.json({ terms: [] });
        }),
      );
      renderRegistration();
      await pageHeading();
      expect(screen.getByText("Loading…")).toBeInTheDocument();
      expect(screen.queryByText("No terms are available.")).not.toBeInTheDocument();

      terms.open();
      expect(await screen.findByText("No terms are available.")).toBeInTheDocument();
      expect(screen.queryByText("Loading…")).not.toBeInTheDocument();
    });

    it("shows the reason when the terms cannot be loaded", async () => {
      server.use(http.get(`${API}/terms`, () => HttpResponse.json(serverError, { status: 500 })));
      renderRegistration();
      expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong. Please try again.");
      expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
      expect(screen.queryByText("No terms are available.")).not.toBeInTheDocument();
    });

    it("shows Loading… until the sections arrive, and not the empty state", async () => {
      const list = gate();
      server.use(
        http.get(`${API}/terms/:termId/sections`, async () => {
          await list.opened;
          return HttpResponse.json({ sections: [] });
        }),
      );
      renderRegistration();
      expect(await screen.findByRole("combobox", { name: "Term" })).toBeInTheDocument();
      expect(screen.getByText("Loading…")).toBeInTheDocument();
      expect(screen.queryByText("No sections are published for this term yet.")).not.toBeInTheDocument();

      list.open();
      expect(await screen.findByText("No sections are published for this term yet.")).toBeInTheDocument();
      expect(screen.queryByText("Loading…")).not.toBeInTheDocument();
    });

    it("shows the reason when the sections cannot be loaded", async () => {
      server.use(http.get(`${API}/terms/:termId/sections`, () => HttpResponse.json(serverError, { status: 500 })));
      renderRegistration();
      expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong. Please try again.");
      expect(screen.getByRole("combobox", { name: "Term" })).toBeInTheDocument();
      expect(screen.queryByText("No sections are published for this term yet.")).not.toBeInTheDocument();
    });

    it("lists nothing until the student's enrolments arrive", async () => {
      const mine = gate();
      server.use(
        http.get(`${API}/me/enrollments`, async () => {
          await mine.opened;
          return HttpResponse.json({ enrollments: [enrollmentIn(cs101Section)] });
        }),
      );
      renderRegistration();
      expect(await screen.findByRole("combobox", { name: "Term" })).toBeInTheDocument();
      expect(await screen.findByText("Loading…")).toBeInTheDocument();
      expect(screen.queryByText(/^CS101 /)).not.toBeInTheDocument();

      mine.open();
      await screen.findByText("CS101 Programming I · Section L1 · 3.5 credits");
      expect(within(rowOf("CS101")).getByText("Your section")).toBeInTheDocument();
      expect(screen.queryByText("Loading…")).not.toBeInTheDocument();
    });

    it("shows the reason, and no buttons, when the student's enrolments cannot be loaded", async () => {
      server.use(http.get(`${API}/me/enrollments`, () => HttpResponse.json(serverError, { status: 500 })));
      renderRegistration();
      expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong. Please try again.");
      expect(screen.queryByText(/^CS101 /)).not.toBeInTheDocument();
      expect(screen.queryByText("No sections are published for this term yet.")).not.toBeInTheDocument();
    });
  });
});
