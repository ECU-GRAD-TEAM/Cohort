import type { QueryClient } from "@tanstack/react-query";
import { act, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { afterEach, describe, expect, it, vi } from "vitest";
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
    await screen.findByRole("navigation", { name: "Main" });
    expect(within(screen.getByRole("banner")).getByText("SS")).toBeInTheDocument();
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

  it("moves focus into the sidebar when the menu opens from the toggle", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    await userEvent.click(await screen.findByRole("button", { name: "Toggle navigation" }));
    const first = within(screen.getByRole("complementary")).getAllByRole("link")[0];
    expect(first).toHaveFocus();
  });

  it("moves focus into the sidebar when the menu opens from More", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const more = within(await screen.findByRole("navigation", { name: "Mobile" })).getByRole("button", {
      name: "More",
    });
    expect(more).toHaveAttribute("aria-expanded", "false");
    expect(more).toHaveAttribute("aria-controls", "sidebar");
    await userEvent.click(more);
    expect(more).toHaveAttribute("aria-expanded", "true");
    expect(within(screen.getByRole("complementary")).getAllByRole("link")[0]).toHaveFocus();
  });

  it("closes on Escape and returns focus to the button that opened it", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const toggle = await screen.findByRole("button", { name: "Toggle navigation" });
    await userEvent.click(toggle);
    await userEvent.keyboard("{Escape}");
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).toHaveFocus();

    const more = within(screen.getByRole("navigation", { name: "Mobile" })).getByRole("button", {
      name: "More",
    });
    await userEvent.click(more);
    await userEvent.keyboard("{Escape}");
    expect(more).toHaveFocus();
  });

  it("has a Close menu button that closes the menu and returns focus to the opener", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const toggle = await screen.findByRole("button", { name: "Toggle navigation" });
    await userEvent.click(toggle);
    await userEvent.click(within(screen.getByRole("complementary")).getByRole("button", { name: "Close menu" }));
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).toHaveFocus();
    expect(screen.getByRole("main")).not.toHaveAttribute("inert");
  });

  describe("when the viewport widens", () => {
    afterEach(() => {
      Reflect.deleteProperty(window, "matchMedia");
    });

    function stubMatchMedia() {
      const listeners = new Set<(event: { matches: boolean }) => void>();
      const removed = vi.fn();
      window.matchMedia = vi.fn((query: string) => ({
        matches: true,
        media: query,
        addEventListener: (_type: string, listener: (event: { matches: boolean }) => void) => listeners.add(listener),
        removeEventListener: (_type: string, listener: (event: { matches: boolean }) => void) => {
          removed();
          listeners.delete(listener);
        },
      })) as unknown as typeof window.matchMedia;
      return { change: (matches: boolean) => listeners.forEach((listener) => listener({ matches })), removed };
    }

    it("closes the open phone menu so nothing is left inert", async () => {
      const media = stubMatchMedia();
      renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
      const toggle = await screen.findByRole("button", { name: "Toggle navigation" });
      await userEvent.click(toggle);
      expect(screen.getByRole("main")).toHaveAttribute("inert");
      act(() => media.change(true)); // still phone width: stays open
      expect(toggle).toHaveAttribute("aria-expanded", "true");
      act(() => media.change(false));
      expect(toggle).toHaveAttribute("aria-expanded", "false");
      expect(screen.getByRole("main")).not.toHaveAttribute("inert");
      expect(screen.getByRole("banner")).not.toHaveAttribute("inert");
    });

    it("stops listening when the shell unmounts", async () => {
      const media = stubMatchMedia();
      const view = renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
      await screen.findByRole("button", { name: "Toggle navigation" });
      view.unmount();
      expect(media.removed).toHaveBeenCalled();
    });
  });

  it("names the signed-in user in the header even when the name is hidden on a phone", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    await screen.findByRole("navigation", { name: "Main" });
    expect(within(screen.getByRole("banner")).getByRole("img", { name: "Signed in as Sara Student" })).toBeInTheDocument();
  });

  it("makes the content behind the open menu inert", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    const toggle = await screen.findByRole("button", { name: "Toggle navigation" });
    const behind = () => [
      screen.getByRole("banner"),
      screen.getByRole("main"),
      screen.getByRole("contentinfo"),
      screen.getByRole("navigation", { name: "Mobile" }),
    ];
    behind().forEach((element) => expect(element).not.toHaveAttribute("inert"));
    await userEvent.click(toggle);
    behind().forEach((element) => expect(element).toHaveAttribute("inert"));
    expect(screen.getByRole("complementary")).not.toHaveAttribute("inert");
    await userEvent.keyboard("{Escape}");
    behind().forEach((element) => expect(element).not.toHaveAttribute("inert"));
  });

  it("shows Loading… inside the shell frame while the user loads", async () => {
    server.use(http.get(`${API}/me`, () => new Promise<never>(() => {})));
    renderApp({ route: "/", auth: createFakeAuth({ session: fakeSession }) });
    // The sign-in check shows its own bare "Loading…" first; wait for the shell's.
    const main = await screen.findByRole("main");
    expect(within(main).getByText("Loading…")).toBeInTheDocument();
    expect(screen.getByRole("contentinfo")).toBeInTheDocument();
  });

  it("shows the page for the route inside the shell", async () => {
    renderApp({ route: "/register", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { name: "Course registration" })).toBeInTheDocument();
    expect(within(screen.getByRole("banner")).getByText("Sara Student")).toBeInTheDocument();
  });

  it("does not show the previous user's data to the next user", async () => {
    const auth = createFakeAuth({ session: fakeSession });
    renderApp({ route: "/", auth });
    await screen.findByRole("navigation", { name: "Main" });
    expect(await within(screen.getByRole("banner")).findByText("Sara Student")).toBeInTheDocument();
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
    await screen.findByRole("navigation", { name: "Main" });
    expect(await within(screen.getByRole("banner")).findByText("Omar Other")).toBeInTheDocument();
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
