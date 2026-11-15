import { useQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { NavLink, Outlet } from "react-router";
import { useAuth } from "./auth/AuthProvider.tsx";
import { BrandMark } from "./components/BrandMark.tsx";
import { ApiError } from "./lib/api.ts";
import { useApi } from "./lib/ApiContext.tsx";
import { formatRole, initials } from "./lib/format.ts";
import { queryKeys } from "./lib/queryKeys.ts";
import { mobileNavPaths, navItems } from "./navigation.ts";

/** The width at which the sidebar becomes the off-canvas phone menu; keep in step with styles.css. */
const PHONE_QUERY = "(max-width: 899px)";

const NOT_LINKED = "Your account is not linked to a university yet. Contact your administrator.";

function Footer({ inert }: { inert?: boolean }) {
  return (
    <footer className="app-footer" inert={inert}>
      <strong>Cohort</strong> <span>Your university, in sync.</span>
    </footer>
  );
}

export function AppShell() {
  const api = useApi();
  const { signOut } = useAuth();
  const me = useQuery({ queryKey: queryKeys.me, queryFn: () => api.getMe() });
  const [menuOpen, setMenuOpen] = useState(false);
  const sidebarRef = useRef<HTMLElement>(null);
  // The button that opened the menu, so Escape can hand focus back to it.
  const openerRef = useRef<HTMLElement | null>(null);
  const restoreFocus = useRef(false);

  useEffect(() => {
    if (menuOpen) {
      sidebarRef.current?.querySelector<HTMLElement>("a")?.focus();
    } else if (restoreFocus.current) {
      restoreFocus.current = false;
      openerRef.current?.focus();
    }
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      restoreFocus.current = true;
      setMenuOpen(false);
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [menuOpen]);

  // Widening past the phone breakpoint hides the menu's controls, so close it rather than leave the
  // page behind it inert.
  useEffect(() => {
    const query = window.matchMedia?.(PHONE_QUERY);
    if (!query) return;
    const onChange = (event: { matches: boolean }) => {
      if (!event.matches) setMenuOpen(false);
    };
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);

  const openMenu = (opener: HTMLElement) => {
    openerRef.current = opener;
    setMenuOpen(true);
  };

  if (me.isPending) {
    return (
      <div className="shell shell-plain">
        <header className="app-header">
          <BrandMark />
        </header>
        <main className="app-main">
          <p>Loading…</p>
        </main>
        <Footer />
      </div>
    );
  }

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
  const closeAndRestoreFocus = () => {
    restoreFocus.current = true;
    setMenuOpen(false);
  };
  const mobileItems = mobileNavPaths.flatMap((path) => navItems.filter((item) => item.to === path));

  return (
    <div className={menuOpen ? "shell menu-open" : "shell"}>
      <aside id="sidebar" className="sidebar" ref={sidebarRef}>
        <button type="button" className="sidebar-close button-secondary" onClick={closeAndRestoreFocus}>
          Close menu
        </button>
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
      <header className="app-header" inert={menuOpen}>
        <button
          type="button"
          className="menu-button"
          aria-label="Toggle navigation"
          aria-expanded={menuOpen}
          aria-controls="sidebar"
          onClick={(event) => (menuOpen ? closeMenu() : openMenu(event.currentTarget))}
        >
          ☰
        </button>
        <div className="header-end">
          <span className="avatar" role="img" aria-label={`Signed in as ${user.displayName}`}>
            {initials(user.displayName)}
          </span>
          <div className="user">
            <span className="user-name">{user.displayName}</span>
            <small>{user.tenant.name}</small>
          </div>
          {signOutButton}
        </div>
      </header>
      <main className="app-main" inert={menuOpen}>
        <Outlet />
      </main>
      <Footer inert={menuOpen} />
      <nav aria-label="Mobile" className="mobile-nav" inert={menuOpen}>
        {mobileItems.map((item) => (
          <NavLink key={item.to} to={item.to} end={item.to === "/"} onClick={closeMenu}>
            {item.label}
          </NavLink>
        ))}
        <button
          type="button"
          aria-expanded={menuOpen}
          aria-controls="sidebar"
          onClick={(event) => openMenu(event.currentTarget)}
        >
          More
        </button>
      </nav>
    </div>
  );
}
