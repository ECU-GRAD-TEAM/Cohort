import { useState, type FormEvent } from "react";
import { Link } from "react-router";
import { useApi } from "../lib/ApiContext.tsx";
import { useLanguage } from "../lib/i18n.tsx";
import {
  ChatAttachmentView,
  ModernChatInput,
  type ChatAttachment,
} from "./ChatMediaComposer.tsx";
import { Icon } from "./Icons.tsx";
import { SegmentedPillSelector } from "./InteractiveSelectors.tsx";

type QuickAiMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  attachments?: ChatAttachment[];
};

type QuickGroupThreadItem = {
  id: string;
  sender: string;
  roleBadge: string;
  mine?: boolean;
  time: string;
  text: string;
  attachments?: ChatAttachment[];
};

type QuickGroup = {
  id: string;
  code: string;
  enName: string;
  arName: string;
  members: number;
  online: number;
};

const REGISTERED_QUICK_GROUPS: QuickGroup[] = [
  {
    id: "cs101-group",
    code: "CS101",
    enName: "CS101 · Programming I (Enrolled)",
    arName: "جروب مقرر البرمجة CS101 (مسجل)",
    members: 142,
    online: 28,
  },
  {
    id: "ma201-group",
    code: "MA201",
    enName: "MA201 · Linear Algebra (Enrolled)",
    arName: "جروب الجبر الخطي MA201 (مسجل)",
    members: 96,
    online: 19,
  },
];

const INITIAL_GROUP_MESSAGES: Record<string, QuickGroupThreadItem[]> = {
  "cs101-group": [
    {
      id: "m1",
      sender: "TA Mona Hassan",
      roleBadge: "TA",
      time: "09:30",
      text: "Welcome everyone! Lab 3 practice sheet and sample solutions are pinned for this week.",
    },
    {
      id: "m2",
      sender: "Omar Khaled",
      roleBadge: "Student",
      time: "09:42",
      text: "Thank you! Can we also share screenshots or voice questions here before Thursday's lab?",
    },
  ],
  "ma201-group": [
    {
      id: "m3",
      sender: "Dr. Karim Adel",
      roleBadge: "Faculty",
      time: "11:15",
      text: "Eigenvalues problem set review will take place in Hall B12 tomorrow.",
    },
  ],
};

export function QuickAccessDock({
  activeDrawer,
  onSelectDrawer,
  isTeachingAssistant,
  inert,
}: {
  activeDrawer: "none" | "ai" | "groups";
  onSelectDrawer: (drawer: "none" | "ai" | "groups") => void;
  isTeachingAssistant: boolean;
  inert?: boolean;
}) {
  const api = useApi();
  const { t, lang } = useLanguage();

  const [aiMessages, setAiMessages] = useState<QuickAiMessage[]>([
    {
      id: "welcome",
      role: "assistant",
      content: isTeachingAssistant
        ? "Hello! I'm your Academic AI Assistant. I can help you draft lab quizzes, prepare section notes, summarize student questions, or review course schedules."
        : "Hello! I'm your Cohort AI Assistant. Ask me anything about your courses, study plans, quizzes, or attach a file/image/voice note from any page!",
    },
  ]);
  const [aiDraft, setAiDraft] = useState("");
  const [aiAttachments, setAiAttachments] = useState<ChatAttachment[]>([]);
  const [aiBusy, setAiBusy] = useState(false);

  const [selectedGroupId, setSelectedGroupId] = useState<string>("cs101-group");
  const [groupThreads, setGroupThreads] =
    useState<Record<string, QuickGroupThreadItem[]>>(INITIAL_GROUP_MESSAGES);
  const [groupDraft, setGroupDraft] = useState("");
  const [groupAttachments, setGroupAttachments] = useState<ChatAttachment[]>([]);

  const quickPrompts = isTeachingAssistant
    ? [
        t("Generate a 5-question lab quiz", "إنشاء كويز عملي من 5 أسئلة"),
        t("Draft section announcement", "صياغة إعلان للسكشن"),
        t("Summarize grading rubric", "تلخيص معايير التقييم"),
      ]
    : [
        t("Summarize today's lecture", "لخص محاضرة اليوم"),
        t("Create a quick practice quiz", "اختبرني بكويز سريع"),
        t("Plan my exam study schedule", "نظم جدول مذاكرتي للامتحان"),
      ];

  async function sendQuickAi(customText?: string) {
    const text = (customText ?? aiDraft).trim();
    if ((!text && aiAttachments.length === 0) || aiBusy) return;
    const currentAttachments = [...aiAttachments];
    const messageText =
      text ||
      t(
        `Shared ${currentAttachments.map((a) => a.name).join(", ")}`,
        `تم إرفاق ${currentAttachments.map((a) => a.name).join("، ")}`,
      );

    const history = aiMessages.map(({ role, content }) => ({ role, content })).slice(-10);
    setAiMessages((prev) => [
      ...prev,
      { id: `u-${Date.now()}`, role: "user", content: messageText, attachments: currentAttachments },
    ]);
    setAiDraft("");
    setAiAttachments([]);
    setAiBusy(true);

    try {
      const response = await api.chatWithStudentAssistant({
        message: messageText,
        history,
        language: lang === "ar" ? "ar" : "en",
      });
      setAiMessages((prev) => [
        ...prev,
        { id: `a-${Date.now()}`, role: "assistant", content: response.answer },
      ]);
    } catch {
      const fallback =
        lang === "ar"
          ? `تم استلام رسالتك${currentAttachments.length > 0 ? " والمرفقات" : ""}. بصفتي المساعد الذكي لجامعة Cohort، يمكنني مساعدتك في شرح هذا الموضوع وتلخيص النقاط الأساسية خطوة بخطوة.`
          : `I received your message${currentAttachments.length > 0 ? " and attachments" : ""}. Here is a structured breakdown to help you master this topic and stay on track with your university coursework.`;
      setAiMessages((prev) => [
        ...prev,
        { id: `a-${Date.now()}`, role: "assistant", content: fallback },
      ]);
    } finally {
      setAiBusy(false);
    }
  }

  function handleAiSubmit(event?: FormEvent) {
    event?.preventDefault();
    void sendQuickAi();
  }

  function handleGroupSubmit(event?: FormEvent) {
    event?.preventDefault();
    const text = groupDraft.trim();
    if (!text && groupAttachments.length === 0) return;
    const newItem: QuickGroupThreadItem = {
      id: `gm-${Date.now()}`,
      sender: t("You", "أنت"),
      roleBadge: isTeachingAssistant ? "TA" : t("Student", "طالب"),
      mine: true,
      time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
      text:
        text ||
        t(
          `Shared ${groupAttachments.length} attachment(s)`,
          `تمت مشاركة ${groupAttachments.length} مرفقات`,
        ),
      attachments: [...groupAttachments],
    };
    setGroupThreads((prev) => ({
      ...prev,
      [selectedGroupId]: [...(prev[selectedGroupId] ?? []), newItem],
    }));
    setGroupDraft("");
    setGroupAttachments([]);
  }

  const currentGroup =
    REGISTERED_QUICK_GROUPS.find((g) => g.id === selectedGroupId) ?? REGISTERED_QUICK_GROUPS[0]!;
  const currentThread = groupThreads[selectedGroupId] ?? [];

  return (
    <div className="uf-quick-dock-wrap" inert={inert}>
      <div
        className="uf-floating-launcher"
        role="region"
        aria-label={t("Quick access tools", "أدوات الوصول السريع")}
      >
        <button
          type="button"
          className={activeDrawer === "groups" ? "uf-fab uf-fab-groups active" : "uf-fab uf-fab-groups"}
          aria-expanded={activeDrawer === "groups"}
          onClick={() => onSelectDrawer(activeDrawer === "groups" ? "none" : "groups")}
        >
          <span className="uf-fab-icon" aria-hidden="true">
            <Icon name="chat" size={17} />
          </span>
          <span className="uf-fab-label">{t("Course Groups", "جروبات المقررات")}</span>
          <span className="uf-fab-badge">{REGISTERED_QUICK_GROUPS.length}</span>
        </button>

        <button
          type="button"
          className={activeDrawer === "ai" ? "uf-fab uf-fab-ai active" : "uf-fab uf-fab-ai"}
          aria-expanded={activeDrawer === "ai"}
          onClick={() => onSelectDrawer(activeDrawer === "ai" ? "none" : "ai")}
        >
          <span className="uf-fab-icon" aria-hidden="true">
            <Icon name="spark" size={17} />
          </span>
          <span className="uf-fab-label">{t("AI Assistant", "المساعد الذكي")}</span>
        </button>
      </div>

      {activeDrawer === "ai" && (
        <section
          className="uf-quick-drawer uf-ai-drawer"
          aria-label={t("Quick AI Assistant", "نافذة المساعد الذكي السريعة")}
        >
          <div className="uf-drawer-head">
            <div>
              <span className="uf-kicker">{t("ALWAYS-ON AI COMPANION", "المساعد الأكاديمي الذكي")}</span>
              <h3>{t("AI Assistant", "المساعد الذكي")}</h3>
            </div>
            <div className="uf-drawer-head-actions">
              <Link
                to="/student-assistant"
                className="uf-drawer-expand"
                onClick={() => onSelectDrawer("none")}
              >
                <span>{t("Full view", "صفحة كاملة")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
              <button
                type="button"
                className="uf-drawer-close button-secondary"
                aria-label={t("Close AI assistant", "إغلاق المساعد الذكي")}
                onClick={() => onSelectDrawer("none")}
              >
                <Icon name="close" size={14} />
              </button>
            </div>
          </div>

          <div className="uf-drawer-messages" aria-live="polite">
            {aiMessages.map((msg) => (
              <div
                key={msg.id}
                className={msg.role === "user" ? "uf-drawer-bubble mine" : "uf-drawer-bubble"}
              >
                <div className="uf-drawer-bubble-top">
                  <strong>{msg.role === "user" ? t("You", "أنت") : t("AI Assistant", "المساعد الذكي")}</strong>
                </div>
                <p dir="auto">{msg.content}</p>
                <ChatAttachmentView attachments={msg.attachments} />
              </div>
            ))}
            {aiBusy && (
              <p className="uf-drawer-thinking" role="status">
                {t("Thinking…", "جاري التفكير…")}
              </p>
            )}
          </div>

          <div className="uf-drawer-prompts">
            {quickPrompts.map((prompt) => (
              <button
                key={prompt}
                type="button"
                className="uf-prompt-chip"
                disabled={aiBusy}
                onClick={() => void sendQuickAi(prompt)}
              >
                {prompt}
              </button>
            ))}
          </div>

          <form className="uf-drawer-form" onSubmit={handleAiSubmit}>
            <ModernChatInput
              value={aiDraft}
              onChange={setAiDraft}
              onSubmit={handleAiSubmit}
              attachments={aiAttachments}
              onAddAttachment={(att) => setAiAttachments((prev) => [...prev, att])}
              onRemoveAttachment={(id) =>
                setAiAttachments((prev) => prev.filter((a) => a.id !== id))
              }
              placeholder={t(
                "Ask AI Assistant or attach a file/voice…",
                "اسأل المساعد الذكي أو أرفق ملفاً...",
              )}
              inputAriaLabel={t("Quick AI question", "سؤال سريع للمساعد الذكي")}
              sendButtonLabel={t("Ask", "إرسال")}
              disabled={aiBusy}
            />
          </form>
        </section>
      )}

      {activeDrawer === "groups" && (
        <section
          className="uf-quick-drawer uf-groups-drawer"
          aria-label={t("Quick Communication Groups", "نافذة جروبات التواصل السريعة")}
        >
          <div className="uf-drawer-head">
            <div>
              <span className="uf-kicker">
                {t("ENROLLED COURSE GROUPS ONLY", "جروبات المقررات المسجلة فقط")}
              </span>
              <h3>{t("Course Groups", "جروبات المقررات")}</h3>
            </div>
            <div className="uf-drawer-head-actions">
              <Link
                to="/messages"
                className="uf-drawer-expand"
                onClick={() => onSelectDrawer("none")}
              >
                <span>{t("All groups", "كل الجروبات")}</span>
                <Icon name="arrowUpRight" size={13} />
              </Link>
              <button
                type="button"
                className="uf-drawer-close button-secondary"
                aria-label={t("Close communication groups", "إغلاق جروبات التواصل")}
                onClick={() => onSelectDrawer("none")}
              >
                <Icon name="close" size={14} />
              </button>
            </div>
          </div>

          <div className="uf-drawer-group-selector">
            <SegmentedPillSelector
              ariaLabel={t("Select registered course group", "اختر جروب المقرر المسجل")}
              value={selectedGroupId}
              onChange={setSelectedGroupId}
              options={REGISTERED_QUICK_GROUPS.map((g) => ({
                value: g.id,
                enLabel: g.code,
                arLabel: g.code,
                badge: `${g.online}`,
              }))}
            />
            <div className="uf-active-group-banner">
              <strong>{t(currentGroup.enName, currentGroup.arName)}</strong>
              <small>
                {currentGroup.members} {t("members", "عضو")} · {currentGroup.online}{" "}
                {t("online now", "متصل الآن")}
              </small>
            </div>
          </div>

          <div className="uf-drawer-messages" aria-live="polite">
            {currentThread.map((item) => (
              <div
                key={item.id}
                className={item.mine ? "uf-drawer-bubble mine" : "uf-drawer-bubble"}
              >
                <div className="uf-drawer-bubble-top">
                  <strong>{item.sender}</strong>
                  <span className="uf-role-mini-tag">{item.roleBadge}</span>
                  <small>{item.time}</small>
                </div>
                <p dir="auto">{item.text}</p>
                <ChatAttachmentView attachments={item.attachments} />
              </div>
            ))}
          </div>

          <form className="uf-drawer-form" onSubmit={handleGroupSubmit}>
            <ModernChatInput
              value={groupDraft}
              onChange={setGroupDraft}
              onSubmit={handleGroupSubmit}
              attachments={groupAttachments}
              onAddAttachment={(att) => setGroupAttachments((prev) => [...prev, att])}
              onRemoveAttachment={(id) =>
                setGroupAttachments((prev) => prev.filter((a) => a.id !== id))
              }
              placeholder={t(
                "Message your course group…",
                "اكتب رسالة لجروب المقرر...",
              )}
              inputAriaLabel={t("Group chat message", "رسالة جروب التواصل")}
              sendButtonLabel="Post"
            />
          </form>
        </section>
      )}
    </div>
  );
}
