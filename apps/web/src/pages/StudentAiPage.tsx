import { useState, type FormEvent } from "react";
import { useApi } from "../lib/ApiContext.tsx";

type Message = { role: "user" | "assistant"; content: string; limitations?: string[] };
const starters = ["Explain a difficult topic", "Create a quick practice quiz", "Help me plan my study week", "Explain a university procedure"];

export function StudentAiPage() {
  const api = useApi();
  const [messages, setMessages] = useState<Message[]>([{ role: "assistant", content: "Hello! I'm your Cohort student assistant. I can help you understand topics, practise, plan your studies and navigate university life. What would you like help with?" }]);
  const [draft, setDraft] = useState("");
  const [language, setLanguage] = useState<"auto" | "en" | "ar">("auto");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function send(text = draft) {
    const message = text.trim();
    if (!message || busy) return;
    const history = messages.map(({ role, content }) => ({ role, content })).slice(-20);
    setMessages(current => [...current, { role: "user", content: message }]);
    setDraft(""); setBusy(true); setError("");
    try {
      const result = await api.chatWithStudentAssistant({ message, history, language });
      setMessages(current => [...current, { role: "assistant", content: result.answer, limitations: result.limitations }]);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The assistant is unavailable. Please try again.");
    } finally { setBusy(false); }
  }

  function submit(event: FormEvent) { event.preventDefault(); void send(); }

  return <main className="student-ai-page" aria-label="Student assistant">
    <header>
      <div><p>COHORT · STUDENT SUPPORT</p><h1>Student assistant</h1><p>Academic help and guidance for your university life.</p></div>
      <label>Language <select value={language} onChange={event => setLanguage(event.target.value as typeof language)}>
        <option value="auto">Automatic</option><option value="en">English</option><option value="ar">العربية</option>
      </select></label>
    </header>
    <section aria-live="polite">
      {messages.map((message, index) => <article key={index} data-role={message.role}>
        <strong>{message.role === "user" ? "You" : "Cohort assistant"}</strong>
        <p dir="auto">{message.content}</p>
        {message.limitations?.map((limitation, i) => <small key={i}>{limitation}</small>)}
      </article>)}
      {busy && <p role="status">Thinking…</p>}
      {error && <p role="alert">{error}</p>}
    </section>
    <section aria-label="Suggested questions">
      <p>Try asking</p>
      {starters.map(starter => <button key={starter} type="button" disabled={busy} onClick={() => void send(starter)}>{starter}</button>)}
    </section>
    <form onSubmit={submit}>
      <textarea value={draft} onChange={event => setDraft(event.target.value)} placeholder="Ask about a course, topic, study strategy or university process…" rows={3} maxLength={12000} />
      <button type="submit" disabled={busy || !draft.trim()}>{busy ? "Sending…" : "Send"}</button>
    </form>
    <p>AI guidance may be incomplete. Verify important university decisions with the relevant department. The assistant cannot change official records.</p>
  </main>;
}
