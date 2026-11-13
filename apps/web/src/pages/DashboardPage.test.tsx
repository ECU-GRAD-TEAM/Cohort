import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, defaultMe, server } from "../../test/server.ts";
import { createFakeAuth, fakeSession, renderApp } from "../../test/render.tsx";

function renderDashboard() {
  return renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
}

describe("DashboardPage", () => {
  it("shows the UniFlow academic workspace to a teaching assistant", async () => {
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

  it("keeps the student dashboard for accounts without the teaching assistant role", async () => {
    server.use(
      http.get(`${API}/me`, () => HttpResponse.json({ ...defaultMe, userType: "student", roles: ["student"] })),
    );
    renderDashboard();
    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: "My courses" })).toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: "Published grades" })).toBeInTheDocument();
  });
});
