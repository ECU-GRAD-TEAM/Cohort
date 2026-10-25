import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, defaultMe, server } from "../test/server.ts";
import { createFakeAuth, fakeSession, renderApp } from "../test/render.tsx";

describe("AppShell", () => {
  it("explains an account that is not linked to a university", async () => {
    server.use(
      http.get(`${API}/me`, () =>
        HttpResponse.json(
          { error: { code: "forbidden", message: "Your account is not linked to a university yet." } },
          { status: 403 },
        ),
      ),
    );
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    expect(
      await screen.findByText("Your account is not linked to a university yet. Contact your administrator."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Dashboard" })).not.toBeInTheDocument();
  });

  it("lets an unlinked account sign out", async () => {
    server.use(
      http.get(`${API}/me`, () =>
        HttpResponse.json(
          { error: { code: "forbidden", message: "Your account is not linked to a university yet." } },
          { status: 403 },
        ),
      ),
    );
    const auth = createFakeAuth({ session: fakeSession });
    renderApp({ route: "/", auth });
    await userEvent.click(await screen.findByRole("button", { name: "Sign out" }));
    expect(auth.signOut).toHaveBeenCalled();
    expect(await screen.findByRole("heading", { name: "Sign in to Cohort" })).toBeInTheDocument();
  });

  it("shows any other error in an alert", async () => {
    server.use(
      http.get(`${API}/me`, () =>
        HttpResponse.json(
          { error: { code: "internal", message: "Something went wrong. Please try again." } },
          { status: 500 },
        ),
      ),
    );
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("alert")).toHaveTextContent("Something went wrong. Please try again.");
    expect(screen.queryByRole("heading", { name: "Dashboard" })).not.toBeInTheDocument();
  });

  it("links to both pages", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/");
    expect(screen.getByRole("link", { name: "Registration" })).toHaveAttribute("href", "/register");
  });

  it("shows the page for the route inside the shell", async () => {
    renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { name: "Course registration" })).toBeInTheDocument();
    expect(screen.getByText("Sara Student · Smoke University A")).toBeInTheDocument();
  });

  it("does not show the previous user's data to the next user", async () => {
    const auth = createFakeAuth({ session: fakeSession });
    renderApp({ route: "/", auth });
    expect(await screen.findByText("Sara Student · Smoke University A")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Sign out" }));
    await screen.findByRole("heading", { name: "Sign in to Cohort" });

    // The next person's /me is held back, so anything on screen meanwhile came from the cache.
    let release!: () => void;
    const held = new Promise<void>((resolve) => {
      release = resolve;
    });
    server.use(
      http.get(`${API}/me`, async () => {
        await held;
        return HttpResponse.json({ ...defaultMe, displayName: "Omar Other" });
      }),
    );
    await userEvent.type(screen.getByLabelText("Email"), "omar@a.test");
    await userEvent.type(screen.getByLabelText("Password"), "secret-pass");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(await screen.findByText("Loading…")).toBeInTheDocument();
    expect(screen.queryByText(/Sara Student/)).not.toBeInTheDocument();
    release();
    expect(await screen.findByText("Omar Other · Smoke University A")).toBeInTheDocument();
  });
});
