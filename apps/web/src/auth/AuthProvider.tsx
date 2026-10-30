import { useQueryClient } from "@tanstack/react-query";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

/** The part of Supabase's auth client the app uses, so tests can supply a fake. */
export type AuthClientLike = Pick<
  SupabaseClient["auth"],
  "getSession" | "onAuthStateChange" | "signInWithPassword" | "signOut"
>;

type AuthValue = {
  session: Session | null;
  /** True until the stored session (if any) has been read. */
  loading: boolean;
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
};

const AuthContext = createContext<AuthValue | null>(null);

export function AuthProvider({ auth, children }: { auth: AuthClientLike; children: ReactNode }) {
  const queryClient = useQueryClient();
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    const { data } = auth.onAuthStateChange((_event, next) => {
      // Whatever ended the session (the button, a rejected token, another tab), the next
      // person to sign in on this browser must not see the last person's data.
      if (next === null) queryClient.clear();
      setSession(next);
      setLoading(false);
    });

    auth.getSession().then(
      ({ data: { session: stored } }) => {
        if (!active) return;
        setSession(stored);
        setLoading(false);
      },
      () => {
        // A failed read counts as signed out, so the visitor reaches the sign-in page.
        if (active) setLoading(false);
      },
    );

    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [auth, queryClient]);

  const value = useMemo<AuthValue>(
    () => ({
      session,
      loading,
      async signIn(email, password) {
        const { error } = await auth.signInWithPassword({ email, password });
        if (error) throw new Error(error.message);
      },
      async signOut() {
        await auth.signOut();
      },
    }),
    [auth, session, loading],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthValue {
  const value = useContext(AuthContext);
  if (value === null) {
    throw new Error("useAuth must be used inside an <AuthProvider>.");
  }
  return value;
}
