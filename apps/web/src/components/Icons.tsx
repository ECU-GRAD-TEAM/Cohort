import type { SVGProps } from "react";

export type IconName =
  | "home"
  | "book"
  | "calendar"
  | "check"
  | "chart"
  | "chat"
  | "grid"
  | "help"
  | "spark"
  | "users"
  | "gear"
  | "shield"
  | "clock"
  | "map"
  | "file"
  | "image"
  | "mic"
  | "plus"
  | "poll"
  | "send"
  | "refresh"
  | "edit"
  | "trash"
  | "globe"
  | "user"
  | "mail"
  | "phone"
  | "award"
  | "arrowUpRight"
  | "close"
  | "menu"
  | "smile"
  | "lock"
  | "bell";

const ICON_PATHS: Record<IconName, string> = {
  home: "M3 10l9-7 9 7M5 9v12h5v-7h4v7h5V9",
  book: "M3 4h7l2 2 2-2h7v16h-7l-2 2-2-2H3zM12 6v16",
  calendar: "M4 5h16v16H4zM4 10h16M8 3v4M16 3v4",
  check: "M9 11l3 3L22 4M20 12v8H4V4h12",
  chart: "M4 20V10h4v10M10 20V4h4v16M16 20v-8h4v8",
  chat: "M4 4h16v13H9l-5 4zM8 8h8M8 12h5",
  grid: "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z",
  help: "M9 9a3 3 0 1 1 4 3c-1 1-1 2-1 3M12 18h.01M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
  spark: "M12 2l3 7 7 3-7 3-3 7-3-7-7-3 7-3z",
  users:
    "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M17 4a4 4 0 0 1 0 8M22 21v-2a4 4 0 0 0-3-4",
  gear: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M3 12h2M19 12h2M12 3v2M12 19v2M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2",
  shield: "M12 3l9 4v6c0 5-9 9-9 9s-9-4-9-9V7zM8 12l3 3 5-6",
  clock: "M12 8v5l4 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
  map: "M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3zM9 3v15M15 6v15",
  file: "M5 3h9l5 5v13H5zM14 3v6h5M8 13h8M8 17h6",
  image: "M4 5h16v14H4zM8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM20 15l-5-5L6 19",
  mic: "M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3zM19 10v2a7 7 0 0 1-14 0v-2M12 19v3M8 22h8",
  plus: "M12 5v14M5 12h14",
  poll: "M4 6h16M4 12h10M4 18h14M18 11v8",
  send: "M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z",
  refresh: "M21 12a9 9 0 0 0-15.36-6.36L3 8M3 3v5h5M3 12a9 9 0 0 0 15.36 6.36L21 16M21 21v-5h-5",
  edit: "M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z",
  trash: "M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6",
  globe:
    "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
  user: "M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
  mail: "M4 4h16v16H4zM22 6l-10 7L2 6",
  phone:
    "M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.79 19.79 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.58 2.81.7A2 2 0 0 1 22 16.92z",
  award: "M12 15a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM8.21 13.89L7 23l5-3 5 3-1.21-9.12",
  arrowUpRight: "M7 17L17 7M7 7h10v10",
  close: "M18 6L6 18M6 6l12 12",
  menu: "M4 6h16M4 12h16M4 18h16",
  smile:
    "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01",
  lock: "M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4",
  bell: "M5 17h14l-2-3V9a5 5 0 0 0-10 0v5zM10 21h4",
};

export function Icon({
  name,
  size = 18,
  className = "uf-svg-icon",
  ...props
}: {
  name: IconName;
  size?: number;
  className?: string;
} & SVGProps<SVGSVGElement>) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
      {...props}
    >
      <path d={ICON_PATHS[name]} />
    </svg>
  );
}
