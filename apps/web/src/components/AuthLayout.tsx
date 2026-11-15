import type { ReactNode } from "react";
import { BrandMark } from "./BrandMark.tsx";

/** The centred card that holds the sign-in and sign-up forms. */
export function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className="auth-page">
      <div className="auth-card">
        <BrandMark />
        <p className="auth-tagline">Your university, in sync.</p>
        {children}
      </div>
    </main>
  );
}
