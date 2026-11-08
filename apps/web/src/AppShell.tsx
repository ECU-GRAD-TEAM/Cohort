import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { NavLink, Outlet } from "react-router";
import { useAuth } from "./auth/AuthProvider.tsx";
import { BrandMark } from "./components/BrandMark.tsx";
import { ApiError } from "./lib/api.ts";
import { useApi } from "./lib/ApiContext.tsx";
import { formatRole, initials } from "./lib/format.ts";
import { queryKeys } from "./lib/queryKeys.ts";
import { mobileNavPaths, navItems } from "./navigation.ts";

const NOT_LINKED = "Your account is not linked to a university yet. Contact your administrator.";

function Footer() {
  return (
    <footer className="app-footer">
      <strong>Cohort</strong> <span>Your university, in sync.</span>
    </footer>
  );
}

export function AppShell() {
  const api = useApi();
  const { signOut } = useAuth();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });
  const [menuOpen, setMenuOpen] = useState(false);

  if (me.isPending) return <p>Loading…</p>;

  const signOutButton = (
    <button type="button" className="button-secondary" onClick={() => void signOut()}>
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
      <div className="shell shell-plain">
        <header className="app-header">
          <BrandMark />
          <div className="header-end">{signOutButton}</div>
        </header>
        <main className="app-main">
          {notLinked ? <p>{NOT_LINKED}</p> : <p role="alert">{error?.message}</p>}
        </main>
        <Footer />
      </div>
    );
  }

  const user = me.data;
  const closeMenu = () => setMenuOpen(false);
  const mobileItems = mobileNavPaths.flatMap((path) => navItems.filter((item) => item.to === path));

  return (
    <div className={menuOpen ? "shell menu-open" : "shell"}>
      <aside id="sidebar" className="sidebar">
        <NavLink to="/" className="brand-link" onClick={closeMenu}>
          <BrandMark />
        </NavLink>
        <div className="university-card">
          <span className="university-name">{user.tenant.name}</span>
          <small>ONE CONNECTED CAMPUS</small>
        </div>
        <div className="workspace">
          <span className="workspace-label">WORKSPACE</span>
          <span className="workspace-role">{formatRole(user)}</span>
        </div>
        <nav aria-label="Main" className="side-nav">
          {navItems.map((item) => (
            <NavLink key={item.to} to={item.to} end={item.to === "/"} onClick={closeMenu}>
              {item.label}
              {item.preview && <span className="preview-tag">Preview</span>}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-foot">
          <b>A little more connected.</b>
          <p>A whole world of possibilities.</p>
          <NavLink to="/campus" className="foot-link" onClick={closeMenu}>
            Explore your campus ↗
          </NavLink>
        </div>
      </aside>
      {menuOpen && <div className="scrim" onClick={closeMenu} aria-hidden="true" />}
      <header className="app-header">
        <button
          type="button"
          className="menu-button"
          aria-label="Toggle navigation"
          aria-expanded={menuOpen}
          aria-controls="sidebar"
          onClick={() => setMenuOpen((open) => !open)}
        >
          ☰
        </button>
        <div className="header-end">
          <span className="avatar" aria-hidden="true">
            {initials(user.displayName)}
          </span>
          <div className="user">
            <span className="user-name">{user.displayName}</span>
            <small>{user.tenant.name}</small>
          </div>
          {signOutButton}
        </div>
      </header>
      <main className="app-main">
        <Outlet />
      </main>
      <Footer />
      <nav aria-label="Mobile" className="mobile-nav">
        {mobileItems.map((item) => (
          <NavLink key={item.to} to={item.to} end={item.to === "/"} onClick={closeMenu}>
            {item.label}
          </NavLink>
        ))}
        <button type="button" onClick={() => setMenuOpen(true)}>
          More
        </button>
      </nav>
    </div>
  );
}
