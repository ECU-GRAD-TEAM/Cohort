import { useState, type FormEvent } from "react";
import { Link, Navigate } from "react-router";
import { useAuth } from "../auth/AuthProvider.tsx";
import { AuthLayout } from "../components/AuthLayout.tsx";

export function SignUpPage() {
  const { session, loading, signUp } = useAuth();
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [confirmedEmail, setConfirmedEmail] = useState<string | null>(null);

  if (loading) return <p>Loading…</p>;
  if (session) return <Navigate to="/" replace />;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const { needsConfirmation } = await signUp(fullName, email, password);
      if (needsConfirmation) setConfirmedEmail(email);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Sign-up failed. Please try again.");
    } finally {
      setSubmitting(false);
    }
  }

  if (confirmedEmail !== null) {
    return (
      <AuthLayout>
        <h1>Create your student account</h1>
        <p role="status">Check your inbox. We sent a confirmation link to {confirmedEmail}.</p>
        <p className="auth-switch">
          <Link to="/login">Back to sign in</Link>
        </p>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout>
      <h1>Create your student account</h1>
      <form onSubmit={handleSubmit}>
        <div>
          <label htmlFor="full-name">Full name</label>
          <input
            id="full-name"
            type="text"
            autoComplete="name"
            required
            value={fullName}
            onChange={(event) => setFullName(event.target.value)}
          />
        </div>
        <div>
          <label htmlFor="email">Email</label>
          <input
            id="email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </div>
        <div>
          <label htmlFor="password">Password</label>
          <input
            id="password"
            type="password"
            autoComplete="new-password"
            required
            aria-describedby="password-hint"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
          <small id="password-hint" className="auth-hint">
            At least 6 characters
          </small>
        </div>
        {error !== null && <p role="alert">{error}</p>}
        <button type="submit" disabled={submitting}>
          Create account
        </button>
      </form>
      <p className="auth-switch">
        Already have an account? <Link to="/login">Sign in</Link>
      </p>
    </AuthLayout>
  );
}
