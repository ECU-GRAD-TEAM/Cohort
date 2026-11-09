/** The Cohort lettermark: a red rounded square with a white "c", then the word. */
export function BrandMark() {
  return (
    <span className="brand">
      <span className="brand-mark" aria-hidden="true">
        c
      </span>
      <span className="brand-name">Cohort</span>
    </span>
  );
}
