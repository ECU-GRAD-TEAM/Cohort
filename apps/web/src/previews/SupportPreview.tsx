import { DISABLED_NOTE, PreviewPage } from "./PreviewPage.tsx";
import { sampleTickets } from "./sampleData.ts";

export function SupportPreview() {
  return (
    <PreviewPage title="Support">
      <div className="preview-split">
        <section className="preview-card">
          <h2>Your requests</h2>
          <ul className="preview-list">
            {sampleTickets.map((ticket) => (
              <li key={ticket.title}>
                <strong>{ticket.title}</strong>
                <span className="preview-muted">{ticket.opened}</span>
                <span className="status-pill">{ticket.status}</span>
              </li>
            ))}
          </ul>
        </section>
        <section className="preview-card">
          <h2>New request</h2>
          <div className="preview-form">
            <label htmlFor="request-subject">Subject</label>
            <input id="request-subject" type="text" disabled aria-describedby="request-note" />
            <label htmlFor="request-details">Details</label>
            <textarea id="request-details" rows={3} disabled aria-describedby="request-note" />
            <button type="button" disabled aria-describedby="request-note">
              Submit request
            </button>
            <span id="request-note" className="preview-muted">
              {DISABLED_NOTE}
            </span>
          </div>
        </section>
      </div>
    </PreviewPage>
  );
}
