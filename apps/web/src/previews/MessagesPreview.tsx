import { DISABLED_NOTE, PreviewPage } from "./PreviewPage.tsx";
import { sampleConversations, sampleThread } from "./sampleData.ts";

export function MessagesPreview() {
  return (
    <PreviewPage title="Messages">
      <div className="preview-split">
        <ul className="preview-list preview-card" aria-label="Conversations">
          {sampleConversations.map((conversation) => (
            <li key={conversation.id}>
              <strong>{conversation.with}</strong>
              <span className="preview-muted">{conversation.last}</span>
            </li>
          ))}
        </ul>
        <div className="preview-card chat">
          <ul className="preview-list" aria-label="Sample thread">
            {sampleThread.map((message) => (
              <li key={message.text} className={message.from === "You" ? "chat-bubble mine" : "chat-bubble"}>
                <strong>{message.from}</strong>
                {message.text}
              </li>
            ))}
          </ul>
          <div className="preview-form">
            <label htmlFor="message-box">Message</label>
            <textarea id="message-box" disabled rows={2} aria-describedby="message-note" />
            <button type="button" disabled aria-describedby="message-note">
              Send
            </button>
            <span id="message-note" className="preview-muted">
              {DISABLED_NOTE}
            </span>
          </div>
        </div>
      </div>
    </PreviewPage>
  );
}
