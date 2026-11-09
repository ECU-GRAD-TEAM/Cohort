import { screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { createFakeAuth, fakeSession, renderApp } from "../../test/render.tsx";
import { server } from "../../test/server.ts";
import { navItems } from "../navigation.ts";

const previews = navItems.filter((item) => item.preview);

describe("preview tabs", () => {
  it("lists Student assistant right after Registration", () => {
    expect(navItems.map((item) => item.label).slice(0, 4)).toEqual([
      "Dashboard",
      "Registration",
      "Student assistant",
      "Courses",
    ]);
  });

  it("has the six preview items in order", () => {
    expect(previews.map((item) => item.to)).toEqual([
      "/courses",
      "/schedule",
      "/assignments",
      "/messages",
      "/support",
      "/campus",
    ]);
  });

  it("sends the old /assistant address to the Student assistant", async () => {
    renderApp({ route: "/assistant", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { level: 1, name: "Student assistant" })).toBeInTheDocument();
  });

  it("has a single assistant in the sidebar", async () => {
    expect(navItems.filter((item) => /assistant/i.test(item.label)).map((item) => item.to)).toEqual([
      "/student-assistant",
    ]);
  });

  it.each(previews.map((item) => [item.label, item.to]))("%s is a labelled preview", async (label, to) => {
    renderApp({ route: to, auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { level: 1, name: label })).toBeInTheDocument();
    expect(screen.getByRole("note")).toHaveTextContent(
      "Preview: sample data. This part of Cohort isn't connected yet.",
    );
    const main = screen.getByRole("navigation", { name: "Main" });
    const link = within(main).getByRole("link", { name: new RegExp(`^${label}`) });
    expect(link).toHaveTextContent("Preview");
  });

  it("the assignments preview includes a sample midterm exam", async () => {
    renderApp({ route: "/assignments", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByText("Sample midterm exam")).toBeInTheDocument();
  });

  it("previews fetch nothing but the signed-in user", async () => {
    const paths: string[] = [];
    const listener = ({ request }: { request: Request }) => {
      paths.push(new URL(request.url).pathname);
    };
    server.events.on("request:start", listener);
    try {
      renderApp({ route: "/courses", auth: createFakeAuth({ session: fakeSession }) });
      await screen.findByRole("heading", { level: 1, name: "Courses" });
      const main = screen.getByRole("navigation", { name: "Main" });
      for (const item of previews.slice(1)) {
        await userEvent.click(within(main).getByRole("link", { name: new RegExp(`^${item.label}`) }));
        await screen.findByRole("heading", { level: 1, name: item.label });
      }
    } finally {
      server.events.removeListener("request:start", listener);
    }
    expect(paths.length).toBeGreaterThan(0);
    expect(paths.every((path) => path === "/me")).toBe(true);
  });

  it.each([
    ["/messages", "Send"],
    ["/support", "Submit request"],
  ])("%s's %s button is disabled", async (path, name) => {
    renderApp({ route: path, auth: createFakeAuth({ session: fakeSession }) });
    const button = await screen.findByRole("button", { name });
    expect(button).toBeDisabled();
    expect(button).toHaveAccessibleDescription("Not available in the preview.");
  });

  it("links the campus preview from the sidebar", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const link = await screen.findByRole("link", { name: "Explore your campus ↗" });
    expect(link).toHaveAttribute("href", "/campus");
  });
});
