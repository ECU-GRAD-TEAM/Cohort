import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { createFakeAuth, fakeSession } from "../../test/render.tsx";
import { AuthProvider, useAuth, type AuthClientLike } from "./AuthProvider.tsx";

function Probe() {
  const { session, loading } = useAuth();
  if (loading) return <p>Loading…</p>;
  return <p>{session ? `Signed in as ${session.user.email}` : "Signed out"}</p>;
}

function renderProvider(auth: AuthClientLike) {
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <AuthProvider auth={auth}>
        <Probe />
      </AuthProvider>
    </QueryClientProvider>,
  );
}

describe("AuthProvider", () => {
  it("reports the stored session once it is read", async () => {
    renderProvider(createFakeAuth({ session: fakeSession }));
    expect(screen.getByText("Loading…")).toBeInTheDocument();
    expect(await screen.findByText("Signed in as sara@a.test")).toBeInTheDocument();
  });

  it("treats a failed session read as signed out", async () => {
    const auth = createFakeAuth({ session: fakeSession });
    vi.mocked(auth.getSession).mockRejectedValueOnce(new Error("storage unavailable"));
    renderProvider(auth);
    expect(await screen.findByText("Signed out")).toBeInTheDocument();
  });

  it("stops listening when it unmounts", async () => {
    const auth = createFakeAuth({ session: null });
    const { unmount } = renderProvider(auth);
    await screen.findByText("Signed out");
    const subscription = vi.mocked(auth.onAuthStateChange).mock.results[0]?.value.data.subscription;
    expect(subscription.unsubscribe).not.toHaveBeenCalled();
    unmount();
    expect(subscription.unsubscribe).toHaveBeenCalledTimes(1);
  });

  it("throws a clear error outside the provider", () => {
    // React logs the render error to the console before rethrowing it.
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    try {
      expect(() => render(<Probe />)).toThrow("useAuth must be used inside an <AuthProvider>.");
    } finally {
      consoleError.mockRestore();
    }
  });
});
