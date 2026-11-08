export type NavItem = { to: string; label: string; preview: boolean };

/** The pages in the sidebar, in order. */
export const navItems: NavItem[] = [
  { to: "/", label: "Dashboard", preview: false },
  { to: "/register", label: "Registration", preview: false },
];

/** The paths shown in the phone bar; each is looked up in `navItems` for its label. */
export const mobileNavPaths: string[] = ["/", "/register"];
