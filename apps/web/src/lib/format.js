// Display helpers for values the API may not have (attendance, progress, grades not yet published).

/** "83%", or "—" when there is no value. */
export const pct = (value) => (value == null ? '—' : `${value}%`);

/** A width for a progress bar: 0 when there is no value. */
export const barWidth = (value) => `${Math.max(0, Math.min(100, value ?? 0))}%`;

/** enrolled / capacity as a whole percentage, or null when either is unknown or capacity is unlimited. */
export const utilisation = (enrolled, capacity) =>
  enrolled == null || !capacity ? null : Math.round((enrolled / capacity) * 100);

/** "25/60", "25" when capacity is unlimited, or "—" when the count is unknown. */
export const seats = (enrolled, capacity) =>
  enrolled == null ? '—' : capacity == null ? String(enrolled) : `${enrolled}/${capacity}`;
