import { useRef, useState, type FormEvent } from "react";
import {
  ChatAttachmentView,
  ModernChatInput,
  type ChatAttachment,
} from "../components/ChatMediaComposer.tsx";
import { Icon } from "../components/Icons.tsx";
import { SegmentedPillSelector } from "../components/InteractiveSelectors.tsx";
import { useApi } from "../lib/ApiContext.tsx";
import { useLanguage } from "../lib/i18n.tsx";

type Message = {
  id: string;
  role: "user" | "assistant";
  content: string;
  limitations?: string[];
  attachments?: ChatAttachment[];
  edited?: boolean;
};

type AiConversation = {
  id: string;
  title: string;
  updatedAt: string;
  messages: Message[];
};

const starters = [
  "Explain a difficult topic",
  "Create a quick practice quiz",
  "Help me plan my study week",
  "Explain a university procedure",
];

function createWelcomeMessage(): Message {
  return {
    id: `welcome-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
    role: "assistant",
    content:
      "Hello! I'm your Cohort student assistant. I can help you understand topics, practise, plan your studies and navigate university life. What would you like help with?",
  };
}

export function StudentAiPage() {
  const api = useApi();
  const { t } = useLanguage();
  const [conversations, setConversations] = useState<AiConversation[]>([
    {
      id: "conv-1",
      title: "Study Plan & Course Overview",
      updatedAt: "Today",
      messages: [createWelcomeMessage()],
    },
    {
      id: "conv-2",
      title: "Data Structures & Trees Review",
      updatedAt: "Yesterday",
      messages: [
        createWelcomeMessage(),
        {
          id: "prev-u1",
          role: "user",
          content: "Explain binary search tree time complexity.",
        },
        {
          id: "prev-a1",
          role: "assistant",
          content:
            "In a balanced binary search tree, lookup, insertion, and deletion operate in O(log n) time because each comparison halves the search space.",
        },
      ],
    },
  ]);
  const [activeConvId, setActiveConvId] = useState<string>("conv-1");
  const [draft, setDraft] = useState("");
  const [attachments, setAttachments] = useState<ChatAttachment[]>([]);
  const [language, setLanguage] = useState<"auto" | "en" | "ar">("auto");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  // Edit & mobile long-press states for sent messages
  const [editingMsgId, setEditingMsgId] = useState<string | null>(null);
  const [editingText, setEditingText] = useState("");
  const [longPressedMsgId, setLongPressedMsgId] = useState<string | null>(null);
  const longPressTimerRef = useRef<number | null>(null);

  const activeConversation =
    conversations.find((c) => c.id === activeConvId) ?? conversations[0]!;
  const messages = activeConversation.messages;

  function updateActiveMessages(updater: (current: Message[]) => Message[], nextTitle?: string) {
    setConversations((prev) =>
      prev.map((conv) => {
        if (conv.id !== activeConversation.id) return conv;
        const updatedMsgs = updater(conv.messages);
        return {
          ...conv,
          title: nextTitle ?? conv.title,
          updatedAt: t("Just now", "الآن"),
          messages: updatedMsgs,
        };
      }),
    );
  }

  function handleNewConversation() {
    const newId = `conv-${Date.now()}`;
    const newConv: AiConversation = {
      id: newId,
      title: `${t("New conversation", "محادثة جديدة")} ${conversations.length + 1}`,
      updatedAt: t("Just now", "الآن"),
      messages: [createWelcomeMessage()],
    };
    setConversations((prev) => [newConv, ...prev]);
    setActiveConvId(newId);
    setDraft("");
    setAttachments([]);
    setError("");
  }

  function handleDeleteConversation(id: string) {
    setConversations((prev) => {
      const remaining = prev.filter((c) => c.id !== id);
      if (remaining.length === 0) {
        const fallback: AiConversation = {
          id: `conv-${Date.now()}`,
          title: t("New conversation", "محادثة جديدة"),
          updatedAt: t("Just now", "الآن"),
          messages: [createWelcomeMessage()],
        };
        setActiveConvId(fallback.id);
        return [fallback];
      }
      if (id === activeConversation.id) {
        setActiveConvId(remaining[0]!.id);
      }
      return remaining;
    });
  }

  async function send(text = draft) {
    const trimmed = text.trim();
    if ((!trimmed && attachments.length === 0) || busy) return;
    const stagedAttachments = [...attachments];
    const message =
      trimmed ||
      t(
        `Attached: ${stagedAttachments.map((a) => a.name).join(", ")}`,
        `مرفقات: ${stagedAttachments.map((a) => a.name).join("، ")}`,
      );
    const history = messages.map(({ role, content }) => ({ role, content })).slice(-20);
    const autoTitle =
      messages.length <= 1 && trimmed ? trimmed.slice(0, 34) : undefined;

    const userMsg: Message = {
      id: `user-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      role: "user",
      content: message,
      attachments: stagedAttachments,
    };

    updateActiveMessages((current) => [...current, userMsg], autoTitle);
    setDraft("");
    setAttachments([]);
    setBusy(true);
    setError("");
    try {
      const result = await api.chatWithStudentAssistant({ message, history, language });
      updateActiveMessages((current) => [
        ...current,
        {
          id: `ai-${Date.now()}`,
          role: "assistant",
          content: result.answer,
          limitations: result.limitations,
        },
      ]);
    } catch (cause) {
      setError(
        cause instanceof Error ? cause.message : "The assistant is unavailable. Please try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  function handleStartEdit(msg: Message) {
    setEditingMsgId(msg.id);
    setEditingText(msg.content);
  }

  function handleSaveEdit(msgId: string) {
    const trimmed = editingText.trim();
    if (!trimmed) return;
    updateActiveMessages((current) =>
      current.map((m) => (m.id === msgId ? { ...m, content: trimmed, edited: true } : m)),
    );
    setEditingMsgId(null);
    setEditingText("");
  }

  function handleTouchStart(msgId: string) {
    longPressTimerRef.current = window.setTimeout(() => {
      setLongPressedMsgId((current) => (current === msgId ? null : msgId));
    }, 450);
  }

  function handleTouchEnd() {
    if (longPressTimerRef.current !== null) {
      window.clearTimeout(longPressTimerRef.current);
      longPressTimerRef.current = null;
    }
  }

  function submit(event?: FormEvent) {
    event?.preventDefault();
    void send();
  }

  return (
    <div className="student-ai-page uf-ai-studio" aria-label="AI Assistant">
      <div className="uf-ai-header">
        <div>
          <p className="uf-kicker">
            {t("UNIFLOW / AI ACADEMIC ASSISTANT", "بوابة الجامعة · المساعد الأكاديمي الذكي")}
          </p>
          <h1>{t("AI Assistant", "المساعد الذكي")}</h1>
          <p className="uf-ai-subtitle">
            {t(
              "Academic help, lecture summaries, quizzes, and guidance with file, image, poll & voice support.",
              "مساعدة أكاديمية، تلخيص محاضرات، اختبارات تدريبية، ودعم كامل للملفات والصور والتسجيل الصوتي.",
            )}
          </p>
        </div>
        <div className="uf-ai-controls">
          <SegmentedPillSelector
            ariaLabel={t("AI Response Language", "لغة رد المساعد الذكي")}
            value={language}
            onChange={setLanguage}
            options={[
              { value: "auto", enLabel: "Auto", arLabel: "تلقائي" },
              { value: "en", enLabel: "English", arLabel: "English" },
              { value: "ar", enLabel: "العربية", arLabel: "العربية" },
            ]}
          />
          <label className="sr-only-input">
            Language{" "}
            <select
              value={language}
              onChange={(event) => setLanguage(event.target.value as typeof language)}
            >
              <option value="auto">Automatic</option>
              <option value="en">English</option>
              <option value="ar">العربية</option>
            </select>
          </label>
        </div>
      </div>

      <div className="uf-ai-workspace-grid">
        {/* Conversations Management Sidebar */}
        <div
          className="uf-ai-conv-sidebar"
          role="region"
          aria-label={t("Conversations history", "سجل المحادثات")}
        >
          <div className="uf-ai-conv-top">
            <span className="uf-kicker">{t("CONVERSATIONS", "المحادثات")}</span>
            <button
              type="button"
              className="uf-new-conv-btn"
              onClick={handleNewConversation}
            >
              <Icon name="plus" size={15} />
              <span>{t("New chat", "محادثة جديدة")}</span>
            </button>
          </div>
          <ul className="uf-ai-conv-list" aria-label="Saved conversations">
            {conversations.map((conv) => {
              const isActive = conv.id === activeConversation.id;
              return (
                <li
                  key={conv.id}
                  className={isActive ? "uf-ai-conv-item active" : "uf-ai-conv-item"}
                >
                  <button
                    type="button"
                    className="uf-ai-conv-select"
                    onClick={() => setActiveConvId(conv.id)}
                  >
                    <Icon name="chat" size={15} />
                    <div className="uf-ai-conv-text">
                      <strong>{conv.title}</strong>
                      <small>{conv.updatedAt}</small>
                    </div>
                  </button>
                  <button
                    type="button"
                    className="uf-ai-conv-delete button-secondary"
                    aria-label={`Delete conversation ${conv.title}`}
                    onClick={() => handleDeleteConversation(conv.id)}
                  >
                    <Icon name="trash" size={14} />
                  </button>
                </li>
              );
            })}
          </ul>
        </div>

        {/* Main Chat Area */}
        <div className="uf-ai-main-pane">
          <section aria-live="polite" className="uf-ai-feed">
            {messages.map((message) => {
              const isUser = message.role === "user";
              const isEditing = editingMsgId === message.id;
              const isLongPressed = longPressedMsgId === message.id;

              return (
                <article
                  key={message.id}
                  data-role={message.role}
                  className={[
                    "uf-ai-message-card",
                    isLongPressed ? "mobile-actions-visible" : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                  onTouchStart={isUser ? () => handleTouchStart(message.id) : undefined}
                  onTouchEnd={isUser ? handleTouchEnd : undefined}
                >
                  <div className="uf-ai-message-meta">
                    <span className="uf-ai-avatar" aria-hidden="true">
                      <Icon name={isUser ? "user" : "spark"} size={14} />
                    </span>
                    <strong>
                      {isUser ? t("You", "أنت") : t("Cohort assistant", "المساعد الذكي")}
                    </strong>
                    {message.edited && (
                      <small className="uf-edited-tag">{t("(edited)", "(معدلة)")}</small>
                    )}

                    {isUser && !isEditing && (
                      <div
                        className="uf-msg-hover-actions"
                        role="group"
                        aria-label={t("Message actions", "إجراءات الرسالة")}
                      >
                        <button
                          type="button"
                          className="uf-msg-action-btn"
                          aria-label={t("Resend message", "إعادة إرسال الرسالة")}
                          title={t("Resend", "إعادة إرسال")}
                          disabled={busy}
                          onClick={() => void send(message.content)}
                        >
                          <Icon name="refresh" size={13} />
                        </button>
                        <button
                          type="button"
                          className="uf-msg-action-btn"
                          aria-label={t("Edit message", "تعديل الرسالة")}
                          title={t("Edit", "تعديل")}
                          onClick={() => handleStartEdit(message)}
                        >
                          <Icon name="edit" size={13} />
                        </button>
                      </div>
                    )}
                  </div>

                  {isEditing ? (
                    <div className="uf-msg-inline-edit">
                      <input
                        type="text"
                        value={editingText}
                        onChange={(e) => setEditingText(e.target.value)}
                        aria-label={t("Edit message text", "نص تعديل الرسالة")}
                      />
                      <div className="uf-msg-inline-edit-btns">
                        <button type="button" onClick={() => handleSaveEdit(message.id)}>
                          {t("Save", "حفظ")}
                        </button>
                        <button
                          type="button"
                          className="button-secondary"
                          onClick={() => setEditingMsgId(null)}
                        >
                          {t("Cancel", "إلغاء")}
                        </button>
                      </div>
                    </div>
                  ) : (
                    <p dir="auto">{message.content}</p>
                  )}

                  <ChatAttachmentView attachments={message.attachments} />
                  {message.limitations?.map((limitation, i) => (
                    <small key={i}>{limitation}</small>
                  ))}
                </article>
              );
            })}
            {busy && <p role="status">{t("Thinking…", "Thinking…")}</p>}
            {error && <p role="alert">{error}</p>}
          </section>

          <section aria-label="Suggested questions" className="student-ai-suggestions">
            <p>{t("Try asking", "جرّب أن تسأل")}</p>
            {starters.map((starter) => (
              <button
                key={starter}
                type="button"
                className="button-secondary uf-starter-chip"
                disabled={busy}
                onClick={() => void send(starter)}
              >
                <Icon name="spark" size={13} />
                <span>{starter}</span>
              </button>
            ))}
          </section>

          <form onSubmit={submit} className="uf-ai-composer-form">
            <ModernChatInput
              value={draft}
              onChange={setDraft}
              onSubmit={submit}
              attachments={attachments}
              onAddAttachment={(att) => setAttachments((prev) => [...prev, att])}
              onRemoveAttachment={(id) =>
                setAttachments((prev) => prev.filter((a) => a.id !== id))
              }
              placeholder={t(
                "Ask about a course, topic, study strategy, or press + to attach…",
                "اسأل عن مقرر، موضوع علمي، أو اضغط + لإرفاق ملف أو صورة أو استطلاع...",
              )}
              inputAriaLabel="Message"
              sendButtonLabel={busy ? "Sending…" : "Send"}
              disabled={busy}
            />
          </form>

          <p className="uf-ai-disclaimer">
            {t(
              "AI guidance may be incomplete. Verify important university decisions with the relevant department. The assistant cannot change official records.",
              "إرشادات الذكاء الاصطناعي استرشادية. يرجى مراجعة القسم الأكاديمي المختص للقرارات الرسمية.",
            )}
          </p>
        </div>
      </div>
    </div>
  );
}
