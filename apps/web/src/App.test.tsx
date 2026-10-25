import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { API, server } from "../test/server.ts";
import { createFakeAuth, fakeSession, renderApp } from "../test/render.tsx";

describe("sign-in", () => {
  it("sends a visitor without a session to sign in", async () => {
    renderApp({ route: "/", auth: createFakeAuth({ session: null }) });
    expect(await screen.findByRole("heading", { name: "Sign in to Cohort" })).toBeInTheDocument();
  });

  it("signs in and shows who is signed in", async () => {
    const auth = createFakeAuth({ session: null });
    renderApp({ route: "/login", auth });
    await userEvent.type(await screen.findByLabelText("Email"), "sara@a.test");
    await userEvent.type(screen.getByLabelText("Password"), "secret-pass");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
    expect(auth.signInWithPassword).toHaveBeenCalledWith({ email: "sara@a.test", password: "secret-pass" });
    expect(await screen.findByText("Sara Student · Smoke University A")).toBeInTheDocument();
  });

  it("shows why sign-in failed", async () => {
    renderApp({
      route: "/login",
      auth: createFakeAuth({ session: null, signInError: "Invalid login credentials" }),
    });
    await userEvent.type(await screen.findByLabelText("Email"), "sara@a.test");
    await userEvent.type(screen.getByLabelText("Password"), "wrong");
    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Invalid login credentials");
  });

  it("returns to sign-in after signing out", async () => {
    const auth = createFakeAuth({ session: fakeSession });
    renderApp({ route: "/", auth });
    await userEvent.click(await screen.findByRole("button", { name: "Sign out" }));
    expect(auth.signOut).toHaveBeenCalled();
    expect(await screen.findByRole("heading", { name: "Sign in to Cohort" })).toBeInTheDocument();
  });

  it("signs the user out when the API rejects the session", async () => {
    server.use(
      http.get(`${API}/me`, () =>
        HttpResponse.json(
          { error: { code: "unauthorized", message: "Sign in to continue." } },
          { status: 401 },
        ),
      ),
    );
    const auth = createFakeAuth({ session: fakeSession });
    renderApp({ route: "/", auth });
    expect(await screen.findByRole("heading", { name: "Sign in to Cohort" })).toBeInTheDocument();
    expect(auth.signOut).toHaveBeenCalled();
  });
});
