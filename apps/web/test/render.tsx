import type { AuthChangeEvent, AuthError, Session } from "@supabase/supabase-js";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { vi } from "vitest";
import { App } from "../src/App.tsx";
import { AuthProvider, type AuthClientLike } from "../src/auth/AuthProvider.tsx";
import { createApiClient } from "../src/lib/api.ts";
import { ApiProvider } from "../src/lib/ApiContext.tsx";
import { API } from "./server.ts";

export const fakeSession = {
  access_token: "test-token",
  user: { id: "0b6a1f4e-3c7d-4e2a-8f19-6d5c4b3a2e10", email: "sara@a.test" },
} as Session;

type Listener = (event: AuthChangeEvent, session: Session | null) => void;

/**
 * A stand-in for Supabase's auth client. It keeps a session in memory and tells every
 * `onAuthStateChange` listener when sign-in or sign-out changes it, as Supabase does.
 */
export function createFakeAuth(options: { session?: Session | null; signInError?: string } = {}): AuthClientLike {
  let session = options.session ?? null;
  const listeners = new Set<Listener>();
  const notify = (event: AuthChangeEvent) => {
    for (const listener of listeners) listener(event, session);
  };

  return {
    getSession: vi.fn(async () =>
      session ? { data: { session }, error: null } : { data: { session: null }, error: null },
    ),
    onAuthStateChange: vi.fn((listener: Listener) => {
      listeners.add(listener);
      const unsubscribe = vi.fn(() => {
        listeners.delete(listener);
      });
      return { data: { subscription: { id: Symbol("subscription"), callback: listener, unsubscribe } } };
    }),
    signInWithPassword: vi.fn(async () => {
      if (options.signInError !== undefined) {
        return {
          data: { session: null, user: null },
          error: { message: options.signInError } as AuthError,
        };
      }
      session = fakeSession;
      notify("SIGNED_IN");
      return { data: { session: fakeSession, user: fakeSession.user }, error: null };
    }),
    signOut: vi.fn(async () => {
      session = null;
      notify("SIGNED_OUT");
      return { error: null };
    }),
  };
}

/**
 * Renders the whole app at `route`, wired as in main.tsx but with the fake auth client. The result
 * also carries the `queryClient`, so a test can refetch to see how the app reacts to a failure.
 */
export function renderApp({ route, auth }: { route: string; auth: AuthClientLike }) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const client = createApiClient({
    baseUrl: API,
    getAccessToken: async () => "test-token",
    onUnauthorized: () => void auth.signOut(),
  });
  const view = render(
    <MemoryRouter initialEntries={[route]}>
      <QueryClientProvider client={queryClient}>
        <AuthProvider auth={auth}>
          <ApiProvider client={client}>
            <App />
          </ApiProvider>
        </AuthProvider>
      </QueryClientProvider>
    </MemoryRouter>,
  );
  return { ...view, queryClient };
}
