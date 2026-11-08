import { DISABLED_NOTE, PreviewPage } from "./PreviewPage.tsx";
import { sampleAnswer, sampleQuestion } from "./sampleData.ts";

export function AssistantPreview() {
  return (
    <PreviewPage title="AI assistant">
      <div className="preview-card chat">
        <p className="chat-bubble mine">
          <strong>You</strong>
          {sampleQuestion}
        </p>
        <p className="chat-bubble">
          <strong>Assistant</strong>
          {sampleAnswer}
        </p>
        <div className="preview-form">
          <label htmlFor="assistant-input">Your question</label>
          <input id="assistant-input" type="text" disabled aria-describedby="assistant-note" />
          <button type="button" disabled aria-describedby="assistant-note">
            Ask
          </button>
          <span id="assistant-note" className="preview-muted">
            {DISABLED_NOTE}
          </span>
        </div>
      </div>
    </PreviewPage>
  );
}
