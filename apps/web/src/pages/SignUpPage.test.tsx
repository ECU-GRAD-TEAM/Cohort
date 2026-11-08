import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { createFakeAuth, fakeSession, renderApp } from "../../test/render.tsx";

async function fillAndSubmit(user: ReturnType<typeof userEvent.setup>) {
  await user.type(await screen.findByLabelText("Full name"), "Nadia New");
  await user.type(screen.getByLabelText("Email"), "nadia@x.test");
  await user.type(screen.getByLabelText("Password"), "secret-pass");
  await user.click(screen.getByRole("button", { name: "Create account" }));
}

describe("SignUpPage", () => {
  it("creates an account and asks the student to confirm their email", async () => {
    const user = userEvent.setup();
    const auth = createFakeAuth();
    renderApp({ route: "/signup", auth });
    await fillAndSubmit(user);

    expect(auth.signUp).toHaveBeenCalledWith({
      email: "nadia@x.test",
      password: "secret-pass",
      options: { data: { full_name: "Nadia New" }, emailRedirectTo: expect.stringMatching(/\/$/) },
    });
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Check your inbox. We sent a confirmation link to nadia@x.test.",
    );
    expect(screen.getByRole("link", { name: "Back to sign in" })).toHaveAttribute("href", "/login");
  });

  it("requires a password of at least 6 characters", async () => {
    renderApp({ route: "/signup", auth: createFakeAuth() });
    expect(await screen.findByLabelText("Password")).toHaveAttribute("minlength", "6");
  });

  it("moves focus to the confirmation message after sign-up", async () => {
    const user = userEvent.setup();
    renderApp({ route: "/signup", auth: createFakeAuth() });
    await fillAndSubmit(user);
    expect(await screen.findByRole("status")).toHaveFocus();
  });

  it("signs the student straight in when no confirmation is needed", async () => {
    const user = userEvent.setup();
    renderApp({ route: "/signup", auth: createFakeAuth({ signUpSession: true }) });
    await fillAndSubmit(user);
    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
  });

  it("shows why sign-up failed", async () => {
    const user = userEvent.setup();
    renderApp({ route: "/signup", auth: createFakeAuth({ signUpError: "User already registered" }) });
    await fillAndSubmit(user);
    expect(await screen.findByRole("alert")).toHaveTextContent("User already registered");
    expect(screen.getByRole("button", { name: "Create account" })).toBeEnabled();
  });

  it("sends a signed-in visitor to the dashboard", async () => {
    renderApp({ route: "/signup", auth: createFakeAuth({ session: fakeSession }) });
    expect(await screen.findByRole("heading", { name: "Dashboard" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Create your student account" })).not.toBeInTheDocument();
  });

  it("links sign-in and sign-up", async () => {
    const login = renderApp({ route: "/login", auth: createFakeAuth() });
    expect(await screen.findByRole("link", { name: "Create an account" })).toHaveAttribute("href", "/signup");
    login.unmount();

    renderApp({ route: "/signup", auth: createFakeAuth() });
    expect(await screen.findByRole("link", { name: "Sign in" })).toHaveAttribute("href", "/login");
    expect(screen.getByText("At least 6 characters")).toBeInTheDocument();
  });
});
