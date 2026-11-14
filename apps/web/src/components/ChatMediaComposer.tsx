import {
  useEffect,
  useId,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent,
  type KeyboardEvent,
} from "react";
import { useLanguage } from "../lib/i18n.tsx";
import { Icon } from "./Icons.tsx";

export type PollOptionItem = {
  id: string;
  text: string;
  votes: number;
};

export type ChatAttachment = {
  id: string;
  kind: "image" | "file" | "voice" | "poll";
  name: string;
  sizeLabel: string;
  url: string;
  durationSec?: number;
  pollQuestion?: string;
  pollOptions?: PollOptionItem[];
};

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60)
    .toString()
    .padStart(2, "0");
  const secs = (seconds % 60).toString().padStart(2, "0");
  return `${mins}:${secs}`;
}

function createSynthesizedVoiceUrl(durationSec: number): string {
  const sampleRate = 8000;
  const numSamples = Math.min(Math.max(durationSec, 1), 5) * sampleRate;
  const buffer = new ArrayBuffer(44 + numSamples);
  const view = new DataView(buffer);
  const writeStr = (offset: number, str: string) => {
    for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
  };
  writeStr(0, "RIFF");
  view.setUint32(4, 36 + numSamples, true);
  writeStr(8, "WAVE");
  writeStr(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate, true);
  view.setUint16(32, 1, true);
  view.setUint16(34, 8, true);
  writeStr(36, "data");
  view.setUint32(40, numSamples, true);
  for (let i = 0; i < numSamples; i++) {
    const tone = Math.sin((2 * Math.PI * 440 * i) / sampleRate) * 18;
    view.setUint8(44 + i, 128 + tone);
  }
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i] ?? 128);
  return `data:audio/wav;base64,${typeof btoa === "function" ? btoa(binary) : ""}`;
}

function PollCard({ attachment }: { attachment: ChatAttachment }) {
  const { t } = useLanguage();
  const [options, setOptions] = useState<PollOptionItem[]>(
    attachment.pollOptions ?? [
      { id: "o1", text: "Yes", votes: 1 },
      { id: "o2", text: "No", votes: 0 },
    ],
  );
  const [votedId, setVotedId] = useState<string | null>(null);
  const totalVotes = options.reduce((acc, item) => acc + item.votes, 0);

  function vote(optionId: string) {
    setOptions((current) =>
      current.map((opt) => {
        if (opt.id === optionId && votedId !== optionId) {
          return { ...opt, votes: opt.votes + 1 };
        }
        if (opt.id === votedId && votedId !== optionId) {
          return { ...opt, votes: Math.max(0, opt.votes - 1) };
        }
        return opt;
      }),
    );
    setVotedId(optionId);
  }

  return (
    <div className="uf-chat-att-poll">
      <div className="uf-poll-head">
        <Icon name="poll" size={16} />
        <strong>{attachment.pollQuestion || attachment.name}</strong>
      </div>
      <div className="uf-poll-options">
        {options.map((opt) => {
          const pct = totalVotes > 0 ? Math.round((opt.votes / totalVotes) * 100) : 0;
          const selected = votedId === opt.id;
          return (
            <button
              key={opt.id}
              type="button"
              className={selected ? "uf-poll-opt selected" : "uf-poll-opt"}
              onClick={() => vote(opt.id)}
            >
              <div className="uf-poll-opt-top">
                <span>{opt.text}</span>
                <small>{`${opt.votes} (${pct}%)`}</small>
              </div>
              <div className="uf-poll-bar">
                <span style={{ width: `${pct}%` }} />
              </div>
            </button>
          );
        })}
      </div>
      <small className="uf-poll-foot">
        {totalVotes} {t("votes · Click an option to vote", "تصويت · اضغط للتصويت")}
      </small>
    </div>
  );
}

export function ChatAttachmentView({ attachments }: { attachments?: ChatAttachment[] }) {
  const { t } = useLanguage();
  if (!attachments || attachments.length === 0) return null;

  return (
    <div className="uf-chat-attachments">
      {attachments.map((att) => {
        if (att.kind === "poll") {
          return <PollCard key={att.id} attachment={att} />;
        }
        if (att.kind === "image") {
          return (
            <figure key={att.id} className="uf-chat-att-image">
              <img src={att.url} alt={att.name} />
              <figcaption>
                <span className="uf-att-caption-label">
                  <Icon name="image" size={14} />
                  <span>{att.name}</span>
                </span>
                <small>{att.sizeLabel}</small>
              </figcaption>
            </figure>
          );
        }
        if (att.kind === "voice") {
          return (
            <div key={att.id} className="uf-chat-att-voice">
              <div className="uf-voice-header">
                <span className="uf-voice-badge">
                  <Icon name="mic" size={14} />
                  <span>{t("Voice Note", "تسجيل صوتي")}</span>
                </span>
                <small>{formatDuration(att.durationSec ?? 3)}</small>
              </div>
              <div className="uf-voice-wave" aria-hidden="true">
                <i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i />
              </div>
              <audio controls src={att.url} preload="metadata" aria-label={att.name} />
            </div>
          );
        }
        return (
          <div key={att.id} className="uf-chat-att-file">
            <span className="uf-file-icon" aria-hidden="true">
              <Icon name="file" size={18} />
            </span>
            <div className="uf-file-meta">
              <strong>{att.name}</strong>
              <small>{att.sizeLabel}</small>
            </div>
            <a href={att.url} download={att.name} className="uf-file-download">
              {t("Download", "تحميل")}
            </a>
          </div>
        );
      })}
    </div>
  );
}

export function ModernChatInput({
  value,
  onChange,
  onSubmit,
  attachments,
  onAddAttachment,
  onRemoveAttachment,
  placeholder,
  disabled = false,
  inputId,
  inputAriaLabel,
  ariaDescribedBy,
  sendButtonLabel = "Send",
}: {
  value: string;
  onChange: (next: string) => void;
  onSubmit: (event?: FormEvent) => void;
  attachments: ChatAttachment[];
  onAddAttachment: (attachment: ChatAttachment) => void;
  onRemoveAttachment: (id: string) => void;
  placeholder: string;
  disabled?: boolean;
  inputId?: string;
  inputAriaLabel?: string;
  ariaDescribedBy?: string;
  sendButtonLabel?: string;
}) {
  const { t } = useLanguage();
  const imageInputId = useId();
  const fileInputId = useId();
  const [plusOpen, setPlusOpen] = useState(false);
  const [pollOpen, setPollOpen] = useState(false);
  const [pollQuestion, setPollQuestion] = useState("");
  const [pollOpt1, setPollOpt1] = useState("");
  const [pollOpt2, setPollOpt2] = useState("");
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const timerRef = useRef<number | null>(null);

  const canSend = (value.trim().length > 0 || attachments.length > 0) && !disabled;

  useEffect(() => {
    if (!recording) {
      if (timerRef.current !== null) {
        window.clearInterval(timerRef.current);
        timerRef.current = null;
      }
      return;
    }
    timerRef.current = window.setInterval(() => {
      setSeconds((s) => s + 1);
    }, 1000);
    return () => {
      if (timerRef.current !== null) {
        window.clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [recording]);

  function handleImageSelect(event: ChangeEvent<HTMLInputElement>) {
    const files = event.target.files;
    if (!files || files.length === 0) return;
    Array.from(files).forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        onAddAttachment({
          id: `img-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
          kind: "image",
          name: file.name,
          sizeLabel: formatBytes(file.size),
          url: typeof reader.result === "string" ? reader.result : "",
        });
      };
      reader.readAsDataURL(file);
    });
    event.target.value = "";
    setPlusOpen(false);
  }

  function handleFileSelect(event: ChangeEvent<HTMLInputElement>) {
    const files = event.target.files;
    if (!files || files.length === 0) return;
    Array.from(files).forEach((file) => {
      const isImg = file.type.startsWith("image/");
      const reader = new FileReader();
      reader.onload = () => {
        onAddAttachment({
          id: `file-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
          kind: isImg ? "image" : "file",
          name: file.name,
          sizeLabel: formatBytes(file.size),
          url: typeof reader.result === "string" ? reader.result : "#",
        });
      };
      reader.readAsDataURL(file);
    });
    event.target.value = "";
    setPlusOpen(false);
  }

  function handleCreatePoll() {
    const q = pollQuestion.trim();
    if (!q) return;
    const o1 = pollOpt1.trim() || t("Agree", "موافق");
    const o2 = pollOpt2.trim() || t("Disagree", "غير موافق");
    onAddAttachment({
      id: `poll-${Date.now()}`,
      kind: "poll",
      name: q,
      sizeLabel: t("Poll", "استطلاع رأي"),
      url: "#",
      pollQuestion: q,
      pollOptions: [
        { id: "opt-1", text: o1, votes: 0 },
        { id: "opt-2", text: o2, votes: 0 },
      ],
    });
    setPollQuestion("");
    setPollOpt1("");
    setPollOpt2("");
    setPollOpen(false);
    setPlusOpen(false);
  }

  function startRecording() {
    if (disabled) return;
    setSeconds(1);
    setRecording(true);
  }

  function stopAndAttachRecording() {
    const dur = Math.max(seconds, 1);
    setRecording(false);
    setSeconds(0);
    onAddAttachment({
      id: `voice-${Date.now()}`,
      kind: "voice",
      name: t(`Voice message (${formatDuration(dur)})`, `رسالة صوتية (${formatDuration(dur)})`),
      sizeLabel: `${dur * 12} KB`,
      url: createSynthesizedVoiceUrl(dur),
      durationSec: dur,
    });
  }

  function cancelRecording() {
    setRecording(false);
    setSeconds(0);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      if (canSend) {
        onSubmit();
      }
    }
  }

  return (
    <div className="uf-media-composer">
      {/* Hidden file/image inputs so labels or menu triggers work reliably */}
      <input
        id={fileInputId}
        type="file"
        multiple
        disabled={disabled}
        onChange={handleFileSelect}
        className="sr-only-input"
        aria-label={t("Upload file", "رفع ملف")}
      />
      <input
        id={imageInputId}
        type="file"
        accept="image/*"
        multiple
        disabled={disabled}
        onChange={handleImageSelect}
        className="sr-only-input"
        aria-label={t("Upload image", "رفع صورة")}
      />

      {attachments.length > 0 && (
        <div
          className="uf-staged-attachments"
          aria-label={t("Attached media", "المرفقات الجاهزة للإرسال")}
        >
          {attachments.map((att) => (
            <div key={att.id} className="uf-staged-chip">
              {att.kind === "image" ? (
                <img src={att.url} alt={att.name} className="uf-staged-thumb" />
              ) : (
                <Icon
                  name={att.kind === "voice" ? "mic" : att.kind === "poll" ? "poll" : "file"}
                  size={14}
                />
              )}
              <span className="uf-staged-name">{att.name}</span>
              <small>{att.sizeLabel}</small>
              <button
                type="button"
                className="uf-staged-remove"
                aria-label={t(`Remove ${att.name}`, `حذف ${att.name}`)}
                onClick={() => onRemoveAttachment(att.id)}
              >
                <Icon name="close" size={12} />
              </button>
            </div>
          ))}
        </div>
      )}

      {plusOpen && (
        <div
          className="uf-plus-popover"
          role="menu"
          aria-label={t("Attachment options", "خيارات الإرفاق")}
        >
          <label htmlFor={fileInputId} className="uf-plus-menu-item" role="menuitem">
            <Icon name="file" size={16} />
            <span>{t("Upload file", "رفع ملف")}</span>
          </label>
          <label htmlFor={imageInputId} className="uf-plus-menu-item" role="menuitem">
            <Icon name="image" size={16} />
            <span>{t("Upload image", "رفع صورة")}</span>
          </label>
          <button
            type="button"
            className="uf-plus-menu-item"
            role="menuitem"
            onClick={() => setPollOpen((prev) => !prev)}
          >
            <Icon name="poll" size={16} />
            <span>{t("Create poll", "إنشاء استطلاع رأي")}</span>
          </button>
        </div>
      )}

      {pollOpen && (
        <div className="uf-poll-builder" role="region" aria-label={t("Poll creator", "إنشاء استطلاع رأي")}>
          <div className="uf-poll-builder-head">
            <strong>
              <Icon name="poll" size={15} /> {t("Create a Poll", "إنشاء استطلاع رأي")}
            </strong>
            <button
              type="button"
              className="button-secondary uf-poll-close"
              onClick={() => setPollOpen(false)}
            >
              <Icon name="close" size={13} />
            </button>
          </div>
          <input
            type="text"
            value={pollQuestion}
            onChange={(e) => setPollQuestion(e.target.value)}
            placeholder={t("Poll question (e.g., Best day for extra lab review?)", "سؤال الاستطلاع...")}
            aria-label={t("Poll question", "سؤال الاستطلاع")}
          />
          <div className="uf-poll-builder-opts">
            <input
              type="text"
              value={pollOpt1}
              onChange={(e) => setPollOpt1(e.target.value)}
              placeholder={t("Option 1 (e.g., Sunday 2 PM)", "الخيار الأول")}
              aria-label={t("Poll option 1", "الخيار الأول")}
            />
            <input
              type="text"
              value={pollOpt2}
              onChange={(e) => setPollOpt2(e.target.value)}
              placeholder={t("Option 2 (e.g., Tuesday 4 PM)", "الخيار الثاني")}
              aria-label={t("Poll option 2", "الخيار الثاني")}
            />
          </div>
          <button
            type="button"
            className="uf-poll-attach-btn"
            disabled={!pollQuestion.trim()}
            onClick={handleCreatePoll}
          >
            {t("Attach Poll", "إرفاق الاستطلاع")}
          </button>
        </div>
      )}

      <div className="uf-modern-chatbox">
        <button
          type="button"
          className={plusOpen ? "uf-chatbox-icon-btn active" : "uf-chatbox-icon-btn"}
          aria-label={t("More attachment options", "إرفاق ملف أو صورة أو استطلاع")}
          aria-expanded={plusOpen}
          disabled={disabled}
          onClick={() => setPlusOpen((prev) => !prev)}
        >
          <Icon name="plus" size={18} />
        </button>

        <textarea
          id={inputId}
          aria-label={inputAriaLabel}
          aria-describedby={ariaDescribedBy}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          rows={1}
          maxLength={12000}
          className="uf-chatbox-input"
        />

        <div className="uf-chatbox-end-actions">
          {!recording ? (
            <button
              type="button"
              className="uf-chatbox-icon-btn uf-mic-trigger"
              aria-label={t("Record voice", "تسجيل صوتي")}
              disabled={disabled}
              onClick={startRecording}
            >
              <Icon name="mic" size={18} />
            </button>
          ) : (
            <div className="uf-recording-inline" role="status" aria-live="polite">
              <span className="uf-rec-dot" aria-hidden="true" />
              <span className="uf-rec-time">{formatDuration(seconds)}</span>
              <button
                type="button"
                className="uf-rec-save"
                aria-label={t("Attach voice", "إرفاق التسجيل")}
                onClick={stopAndAttachRecording}
              >
                <Icon name="check" size={14} />
                <span>{t("Attach voice", "إرفاق")}</span>
              </button>
              <button
                type="button"
                className="uf-rec-cancel button-secondary"
                aria-label={t("Cancel recording", "إلغاء التسجيل")}
                onClick={cancelRecording}
              >
                <Icon name="close" size={14} />
              </button>
            </div>
          )}

          <button
            type="submit"
            className="uf-chatbox-send-btn"
            aria-label={sendButtonLabel}
            aria-describedby={ariaDescribedBy}
            disabled={!canSend}
          >
            <Icon name="send" size={17} />
          </button>
        </div>
      </div>
    </div>
  );
}
