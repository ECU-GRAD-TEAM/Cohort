import { useQuery } from "@tanstack/react-query";
import { NavLink, Outlet } from "react-router";
import { useAuth } from "./auth/AuthProvider.tsx";
import { ApiError } from "./lib/api.ts";
import { useApi } from "./lib/ApiContext.tsx";
import { queryKeys } from "./lib/queryKeys.ts";

const NOT_LINKED = "Your account is not linked to a university yet. Contact your administrator.";

export function AppShell() {
  const api = useApi();
  const { signOut } = useAuth();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });

  if (me.isPending) return <p>Loading…</p>;

  const signOutButton = (
    <button type="button" onClick={() => void signOut()}>
      Sign out
    </button>
  );

  if (me.isError) {
    const error = me.error;
    const notLinked = error instanceof ApiError && error.status === 403 && error.code === "forbidden";
    return (
      <>
        <header>{signOutButton}</header>
        <main>{notLinked ? <p>{NOT_LINKED}</p> : <p role="alert">{error.message}</p>}</main>
      </>
    );
  }

  return (
    <>
      <header>
        <p>{`${me.data.displayName} · ${me.data.tenant.name}`}</p>
        <nav aria-label="Main">
          <NavLink to="/" end>
            Dashboard
          </NavLink>{" "}
          <NavLink to="/register">Registration</NavLink>
        </nav>
        {signOutButton}
      </header>
      <main>
        <Outlet />
      </main>
    </>
  );
}
