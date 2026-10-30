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

  // A 403 means the account has no university, now or since the page loaded, so it ends the page
  // even when an earlier answer is still cached. Any other failure only matters when there is
  // nothing to show: a refetch (on tab focus or reconnect) that fails keeps the loaded page.
  const error = me.error;
  const notLinked = error instanceof ApiError && error.status === 403 && error.code === "forbidden";
  if (notLinked || me.data === undefined) {
    return (
      <>
        <header>{signOutButton}</header>
        <main>{notLinked ? <p>{NOT_LINKED}</p> : <p role="alert">{error?.message}</p>}</main>
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
          <NavLink to="/register">Registration</NavLink>{" "}
          <NavLink to="/student-assistant">Student assistant</NavLink>
        </nav>
        {signOutButton}
      </header>
      <main>
        <Outlet />
      </main>
    </>
  );
}
