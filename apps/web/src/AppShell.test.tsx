import type { QueryClient } from "@tanstack/react-query";
import { act, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { queryKeys } from "./lib/queryKeys.ts";
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
    expect(screen.queryByRole("navigation", { name: "Main" })).not.toBeInTheDocument();
    expect(screen.queryByRole("navigation", { name: "Mobile" })).not.toBeInTheDocument();
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
    const main = within(await screen.findByRole("navigation", { name: "Main" }));
    expect(main.getByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/");
    expect(main.getByRole("link", { name: "Registration" })).toHaveAttribute("href", "/register");
  });

  it("shows the student's university and role in the sidebar", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const sidebar = within(await screen.findByRole("complementary"));
    expect(sidebar.getByText("Smoke University A")).toBeInTheDocument();
    expect(sidebar.getByText("ONE CONNECTED CAMPUS")).toBeInTheDocument();
    expect(sidebar.getByText("WORKSPACE")).toBeInTheDocument();
    expect(sidebar.getByText("Student")).toBeInTheDocument();
  });

  it("shows the student's initials", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    expect(within(await screen.findByRole("banner")).getByText("SS")).toBeInTheDocument();
  });

  it("opens and closes the menu on a phone", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const toggle = await screen.findByRole("button", { name: "Toggle navigation" });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(toggle);
    expect(toggle).toHaveAttribute("aria-expanded", "true");
    await userEvent.click(
      within(screen.getByRole("navigation", { name: "Main" })).getByRole("link", { name: "Registration" }),
    );
    expect(toggle).toHaveAttribute("aria-expanded", "false");
  });

  it("opens the menu from the More button on the phone bar", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const toggle = await screen.findByRole("button", { name: "Toggle navigation" });
    const mobile = within(screen.getByRole("navigation", { name: "Mobile" }));
    expect(mobile.getByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/");
    await userEvent.click(mobile.getByRole("button", { name: "More" }));
    expect(toggle).toHaveAttribute("aria-expanded", "true");
  });

  it("shows the page for the route inside the shell", async () => {
    renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { name: "Course registration" })).toBeInTheDocument();
    expect(within(screen.getByRole("banner")).getByText("Sara Student")).toBeInTheDocument();
  });

  it("does not show the previous user's data to the next user", async () => {
    const auth = createFakeAuth({ session: fakeSession });
    renderApp({ route: "/", auth });
    expect(await within(await screen.findByRole("banner")).findByText("Sara Student")).toBeInTheDocument();
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
    expect(await within(await screen.findByRole("banner")).findByText("Omar Other")).toBeInTheDocument();
  });

  describe("when /me is refetched after the shell has loaded", () => {
    // The refetch runs on tab focus and reconnect; the test triggers it directly.
    async function refetchMe(queryClient: QueryClient) {
      await act(async () => {
        await queryClient.refetchQueries({ queryKey: queryKeys.me });
        // TanStack Query hands the result to React from a zero-delay timer. Waiting for one more
        // keeps a "nothing changed" assertion from passing before the failure has reached the page.
        await new Promise((resolve) => setTimeout(resolve, 0));
      });
    }

    it("keeps the page when the refetch fails", async () => {
      const { queryClient } = renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
      expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();

      server.use(
        http.get(`${API}/me`, () =>
          HttpResponse.json(
            { error: { code: "internal", message: "Something went wrong. Please try again." } },
            { status: 500 },
          ),
        ),
      );
      await refetchMe(queryClient);

      // The refetch really failed, yet the page and the signed-in line stay.
      expect(queryClient.getQueryState(queryKeys.me)?.status).toBe("error");
      expect(screen.getByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
      expect(within(screen.getByRole("banner")).getByText("Sara Student")).toBeInTheDocument();
      expect(
        within(screen.getByRole("navigation", { name: "Main" })).getByRole("link", { name: "Registration" }),
      ).toBeInTheDocument();
      expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    });

    it("replaces the page with the unlinked notice when the refetch says the account is no longer linked", async () => {
      const { queryClient } = renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
      expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();

      server.use(
        http.get(`${API}/me`, () =>
          HttpResponse.json(
            { error: { code: "forbidden", message: "Your account is not linked to a university yet." } },
            { status: 403 },
          ),
        ),
      );
      await refetchMe(queryClient);

      expect(
        screen.getByText("Your account is not linked to a university yet. Contact your administrator."),
      ).toBeInTheDocument();
      expect(screen.queryByRole("heading", { name: "Dashboard" })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: "Sign out" })).toBeInTheDocument();
    });
  });
});
