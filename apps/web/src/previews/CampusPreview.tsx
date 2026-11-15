import { PreviewPage } from "./PreviewPage.tsx";
import { samplePlaces } from "./sampleData.ts";

export function CampusPreview() {
  return (
    <PreviewPage title="Campus">
      <div className="preview-split">
        <div className="map-placeholder" role="img" aria-label="Sample campus map placeholder">
          Sample map
        </div>
        <ul className="preview-list preview-card" aria-label="Buildings and services">
          {samplePlaces.map((place) => (
            <li key={place.name}>
              <strong>{place.name}</strong>
              <span className="preview-muted">
                {place.kind} · {place.note}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </PreviewPage>
  );
}
