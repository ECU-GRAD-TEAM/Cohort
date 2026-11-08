export type NavItem = { to: string; label: string; preview: boolean };

/** The pages in the sidebar, in order. */
export const navItems: NavItem[] = [
  { to: "/", label: "Dashboard", preview: false },
  { to: "/register", label: "Registration", preview: false },
  { to: "/student-assistant", label: "Student assistant", preview: false },
  { to: "/courses", label: "Courses", preview: true },
  { to: "/schedule", label: "Schedule", preview: true },
  { to: "/assignments", label: "Assignments", preview: true },
  { to: "/messages", label: "Messages", preview: true },
  { to: "/support", label: "Support", preview: true },
  { to: "/campus", label: "Campus", preview: true },
  { to: "/assistant", label: "AI assistant", preview: true },
];

/** The paths shown in the phone bar; each is looked up in `navItems` for its label. */
export const mobileNavPaths: string[] = ["/", "/register", "/courses", "/schedule"];
