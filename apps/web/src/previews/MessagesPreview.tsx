import type { EnrollmentsResponse } from "@cohort/contracts";
import { useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type FormEvent } from "react";
import {
  ChatAttachmentView,
  ModernChatInput,
  type ChatAttachment,
} from "../components/ChatMediaComposer.tsx";
import { Icon } from "../components/Icons.tsx";
import { useLanguage } from "../lib/i18n.tsx";
import { queryKeys } from "../lib/queryKeys.ts";
import { DISABLED_NOTE, PreviewPage } from "./PreviewPage.tsx";
import { sampleConversations, sampleThread } from "./sampleData.ts";

const WHATSAPP_REACTIONS = [
  { emoji: "❤️", label: "Heart" },
  { emoji: "😂", label: "Laugh" },
  { emoji: "😢", label: "Sad" },
  { emoji: "😡", label: "Angry" },
  { emoji: "👍", label: "Like" },
] as const;

type RichThreadMessage = {
  id: string;
  from: string;
  text: string;
  time?: string;
  roleTag?: string;
  edited?: boolean;
  reactions?: Record<string, number>;
  myReaction?: string | null;
  attachments?: ChatAttachment[];
};

const LOCKED_UNREGISTERED_GROUPS = [
  { code: "CS410", name: "Cloud Architecture & DevOps", reason: "Not registered this term" },
  { code: "AI405", name: "Deep Reinforcement Learning", reason: "Not registered this term" },
];

export function MessagesPreview() {
  const { t } = useLanguage();
  const queryClient = useQueryClient();
  const cachedEnrollments = queryClient.getQueryData<EnrollmentsResponse>(queryKeys.enrollments);
  const enrolledCourses =
    cachedEnrollments?.enrollments.filter((e) => e.status === "enrolled") ?? [];

  const [activeConvId, setActiveConvId] = useState<string>(sampleConversations[0]?.id ?? "one");
  const [draft, setDraft] = useState("");
  const [attachments, setAttachments] = useState<ChatAttachment[]>([]);
  const [openReactionPickerId, setOpenReactionPickerId] = useState<string | null>(null);
  const [editingMsgId, setEditingMsgId] = useState<string | null>(null);
  const [editingText, setEditingText] = useState("");
  const [longPressedMsgId, setLongPressedMsgId] = useState<string | null>(null);
  const longPressTimerRef = useRef<number | null>(null);

  const [threads, setThreads] = useState<Record<string, RichThreadMessage[]>>({
    one: sampleThread.map((m, idx) => ({
      id: `init-${idx}`,
      from: m.from,
      text: m.text,
      time: idx === 0 ? "10:15 AM" : "10:18 AM",
      roleTag: m.from === "You" ? "Enrolled Student" : "Course Instructor",
      reactions: (idx === 0 ? { "❤️": 2 } : {}) as Record<string, number>,
      myReaction: null,
    })),
    two: [
      {
        id: "adv-1",
        from: "Sample Advisor",
        text: "Reminder: Academic advising & graduation project registration window is open this week.",
        time: "09:00 AM",
        roleTag: "Academic Advisor",
        reactions: {},
        myReaction: null,
      },
    ],
    three: [
      {
        id: "grp-1",
        from: "Sample study group",
        text: "Welcome to your registered course group! Share files, images, polls, or voice notes with your classmates.",
        time: "11:30 AM",
        roleTag: "Registered Cohort Group",
        reactions: { "👍": 4 },
        myReaction: null,
      },
    ],
  });

  const canSend = draft.trim().length > 0 || attachments.length > 0;
  const activeConversation =
    sampleConversations.find((c) => c.id === activeConvId) ?? sampleConversations[0]!;
  const currentMessages = threads[activeConvId] ?? threads.one ?? [];

  function updateCurrentThread(updater: (list: RichThreadMessage[]) => RichThreadMessage[]) {
    setThreads((prev) => ({
      ...prev,
      [activeConvId]: updater(prev[activeConvId] ?? []),
    }));
  }

  function handleSend(event?: FormEvent) {
    event?.preventDefault();
    if (!canSend) return;
    const text =
      draft.trim() ||
      t(
        `Shared ${attachments.map((a) => a.name).join(", ")}`,
        `تمت مشاركة ${attachments.map((a) => a.name).join("، ")}`,
      );
    const nextMsg: RichThreadMessage = {
      id: `msg-${Date.now()}`,
      from: "You",
      text,
      time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
      roleTag: t("You", "أنت"),
      reactions: {},
      myReaction: null,
      attachments: [...attachments],
    };
    updateCurrentThread((list) => [...list, nextMsg]);
    setDraft("");
    setAttachments([]);
  }

  function handleDeleteOwnMessage(msgId: string) {
    updateCurrentThread((list) => list.filter((m) => !(m.id === msgId && m.from === "You")));
  }

  function handleStartEditOwnMessage(msg: RichThreadMessage) {
    if (msg.from !== "You") return;
    setEditingMsgId(msg.id);
    setEditingText(msg.text);
  }

  function handleSaveEditOwnMessage(msgId: string) {
    const trimmed = editingText.trim();
    if (!trimmed) return;
    updateCurrentThread((list) =>
      list.map((m) =>
        m.id === msgId && m.from === "You" ? { ...m, text: trimmed, edited: true } : m,
      ),
    );
    setEditingMsgId(null);
    setEditingText("");
  }

  function handleToggleReaction(msgId: string, emoji: string) {
    updateCurrentThread((list) =>
      list.map((m) => {
        if (m.id !== msgId) return m;
        const currentReactions = { ...(m.reactions ?? {}) };
        const previousEmoji = m.myReaction;

        if (previousEmoji) {
          const prevCount = currentReactions[previousEmoji] ?? 1;
          if (prevCount <= 1) delete currentReactions[previousEmoji];
          else currentReactions[previousEmoji] = prevCount - 1;
        }

        if (previousEmoji === emoji) {
          return { ...m, reactions: currentReactions, myReaction: null };
        }

        currentReactions[emoji] = (currentReactions[emoji] ?? 0) + 1;
        return { ...m, reactions: currentReactions, myReaction: emoji };
      }),
    );
    setOpenReactionPickerId(null);
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

  return (
    <PreviewPage title="Messages">
      <div className="uf-access-guard-bar">
        <div className="uf-access-guard-title">
          <Icon name="shield" size={18} />
          <div>
            <strong>
              {t(
                "Registered Course Groups Access Control",
                "صلاحية الوصول مقصورة على جروبات المقررات المسجلة فقط",
              )}
            </strong>
            <small>
              {enrolledCourses.length > 0
                ? t(
                    `Active access verified for ${enrolledCourses.map((e) => e.course.code).join(", ")}. Non-registered course groups are locked.`,
                    `تم تفعيل الوصول لمقرراتك المسجلة (${enrolledCourses.map((e) => e.course.code).join("، ")}). جروبات المقررات غير المسجلة مغلقة.`,
                  )
                : t(
                    "You can only view and communicate in groups for your strictly registered courses.",
                    "يمكنك فقط الدخول والتفاعل في جروبات المقررات المسجلة لك رسمياً هذا الفصل.",
                  )}
            </small>
          </div>
        </div>
        <span className="uf-verified-enrollment-pill">
          <Icon name="check" size={13} />
          <span>{t("Enrolled Courses Only", "المقررات المسجلة فقط")}</span>
        </span>
      </div>

      <div className="preview-split uf-chat-hub">
        <div className="preview-card uf-conversations-sidebar">
          <div className="uf-panel-head">
            <div>
              <span className="uf-kicker">
                {t("ENROLLED COURSE CHANNELS", "جروبات مقرراتك المسجلة")}
              </span>
              <h2>{t("Registered groups", "الجروبات المتاحة لك")}</h2>
            </div>
            <span className="uf-chat-online-pill">
              <Icon name="check" size={12} /> {t("Verified", "مفعّل")}
            </span>
          </div>

          <ul className="preview-list" aria-label="Conversations">
            {sampleConversations.map((conversation, index) => {
              const active = conversation.id === activeConvId;
              const courseTag =
                enrolledCourses[index]?.course.code ?? ["CS101", "MA201", "CS201"][index] ?? "COURSE";
              return (
                <li
                  key={conversation.id}
                  className={active ? "uf-conv-item active" : "uf-conv-item"}
                  onClick={() => setActiveConvId(conversation.id)}
                >
                  <div className="uf-conv-item-head">
                    <strong>{conversation.with}</strong>
                    <span className="uf-conv-badge">{courseTag} · Enrolled</span>
                  </div>
                  <span className="preview-muted">{conversation.last}</span>
                </li>
              );
            })}
          </ul>

          <div className="uf-locked-groups-section">
            <span className="uf-kicker">
              {t("UNREGISTERED COURSES (LOCKED)", "مقررات غير مسجلة (مغلقة)")}
            </span>
            <ul className="uf-locked-groups-list" aria-label="Locked unregistered course groups">
              {LOCKED_UNREGISTERED_GROUPS.map((grp) => (
                <li key={grp.code} className="uf-locked-group-item" aria-disabled="true">
                  <Icon name="lock" size={15} />
                  <div>
                    <strong>{`${grp.code} · ${grp.name}`}</strong>
                    <small>{t(grp.reason, "غير مسجل في جدولك الحالي")}</small>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="preview-card chat uf-chat-room">
          <div className="uf-chat-room-head">
            <div>
              <span className="uf-kicker">
                {t("REGISTERED COURSE GROUP CHAT", "محادثة جروب المقرر المسجل")}
              </span>
              <h2>{activeConversation.with}</h2>
            </div>
            <div className="uf-chat-room-badges">
              <span className="uf-media-cap-pill">
                <Icon name="file" size={12} /> {t("Files", "ملفات")}
              </span>
              <span className="uf-media-cap-pill">
                <Icon name="image" size={12} /> {t("Images", "صور")}
              </span>
              <span className="uf-media-cap-pill">
                <Icon name="poll" size={12} /> {t("Polls", "استطلاعات")}
              </span>
              <span className="uf-media-cap-pill">
                <Icon name="mic" size={12} /> {t("Voice", "صوت")}
              </span>
            </div>
          </div>

          <ul className="preview-list uf-chat-thread" aria-label="Sample thread">
            {currentMessages.map((message) => {
              const isMine = message.from === "You";
              const isEditing = editingMsgId === message.id;
              const isPickerOpen = openReactionPickerId === message.id;
              const isLongPressed = longPressedMsgId === message.id;
              const reactionEntries = Object.entries(message.reactions ?? {}).filter(
                ([, count]) => count > 0,
              );

              return (
                <li
                  key={message.id}
                  className={[
                    isMine ? "chat-bubble mine" : "chat-bubble",
                    isLongPressed ? "mobile-actions-visible" : "",
                  ]
                    .filter(Boolean)
                    .join(" ")}
                  onTouchStart={() => handleTouchStart(message.id)}
                  onTouchEnd={handleTouchEnd}
                >
                  {/* WhatsApp-style Floating Reaction Picker Bar */}
                  <div
                    className={
                      isPickerOpen
                        ? "uf-wa-reaction-bar open"
                        : "uf-wa-reaction-bar"
                    }
                    role="toolbar"
                    aria-label={`Reactions for message from ${message.from}`}
                  >
                    {WHATSAPP_REACTIONS.map((item) => (
                      <button
                        key={item.label}
                        type="button"
                        className={
                          message.myReaction === item.emoji
                            ? "uf-wa-react-btn selected"
                            : "uf-wa-react-btn"
                        }
                        aria-label={`React with ${item.label}`}
                        onClick={() => handleToggleReaction(message.id, item.emoji)}
                      >
                        {item.emoji}
                      </button>
                    ))}
                  </div>

                  <div className="uf-bubble-header">
                    <strong>{message.from}</strong>
                    <div className="uf-bubble-header-end">
                      {message.edited && (
                        <small className="uf-edited-tag">{t("(edited)", "(معدلة)")}</small>
                      )}
                      {message.time && <small>{message.time}</small>}

                      <div className="uf-msg-hover-actions">
                        <button
                          type="button"
                          className="uf-msg-action-btn"
                          aria-label={`Add reaction to message from ${message.from}`}
                          onClick={() =>
                            setOpenReactionPickerId((cur) =>
                              cur === message.id ? null : message.id,
                            )
                          }
                        >
                          <Icon name="smile" size={13} />
                        </button>

                        {/* Users can ONLY Edit or Delete their own sent messages */}
                        {isMine && !isEditing && (
                          <>
                            <button
                              type="button"
                              className="uf-msg-action-btn"
                              aria-label="Edit own message"
                              onClick={() => handleStartEditOwnMessage(message)}
                            >
                              <Icon name="edit" size={13} />
                            </button>
                            <button
                              type="button"
                              className="uf-msg-action-btn uf-msg-delete-btn"
                              aria-label="Delete own message"
                              onClick={() => handleDeleteOwnMessage(message.id)}
                            >
                              <Icon name="trash" size={13} />
                            </button>
                          </>
                        )}
                      </div>
                    </div>
                  </div>

                  {isEditing ? (
                    <div className="uf-msg-inline-edit">
                      <input
                        type="text"
                        value={editingText}
                        onChange={(e) => setEditingText(e.target.value)}
                        aria-label="Edit own message text"
                      />
                      <div className="uf-msg-inline-edit-btns">
                        <button
                          type="button"
                          onClick={() => handleSaveEditOwnMessage(message.id)}
                        >
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
                    <span className="uf-bubble-text">{message.text}</span>
                  )}

                  <ChatAttachmentView attachments={message.attachments} />

                  {reactionEntries.length > 0 && (
                    <div className="uf-wa-reaction-pills">
                      {reactionEntries.map(([emoji, count]) => (
                        <button
                          key={emoji}
                          type="button"
                          className={
                            message.myReaction === emoji
                              ? "uf-wa-reaction-pill mine"
                              : "uf-wa-reaction-pill"
                          }
                          onClick={() => handleToggleReaction(message.id, emoji)}
                        >
                          <span>{emoji}</span>
                          <small>{count}</small>
                        </button>
                      ))}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>

          <form className="preview-form uf-rich-chat-form" onSubmit={handleSend}>
            <label htmlFor="message-box" className="sr-only-input">
              Message
            </label>
            <ModernChatInput
              inputId="message-box"
              value={draft}
              onChange={setDraft}
              onSubmit={handleSend}
              attachments={attachments}
              onAddAttachment={(att) => setAttachments((prev) => [...prev, att])}
              onRemoveAttachment={(id) =>
                setAttachments((prev) => prev.filter((a) => a.id !== id))
              }
              placeholder={t(
                "Type a message, press Enter to send, or click + for files/images/polls…",
                "اكتب رسالة واضغط Enter للإرسال، أو اضغط + لرفع ملفات/صور/استطلاع...",
              )}
              ariaDescribedBy="message-note"
              sendButtonLabel="Send"
            />
            <span id="message-note" className="preview-muted">
              {DISABLED_NOTE}
            </span>
          </form>
        </div>
      </div>
    </PreviewPage>
  );
}
