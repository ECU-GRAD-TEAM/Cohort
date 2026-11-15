import React from 'react';
import {
  Home,
  BookOpen,
  CalendarDays,
  Sparkles,
  MessageSquare,
  ClipboardEdit,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';

export function FloatingDock() {
  const { role, page, navigate, t } = useCohort();

  const studentItems = [
    { id: 'dashboard', label: t('Home', 'الرئيسية'), Icon: Home },
    { id: 'courses', label: t('Courses', 'المقررات'), Icon: BookOpen },
    { id: 'schedule', label: t('Schedule', 'الجدول'), Icon: CalendarDays },
    { id: 'assistant', label: t('AI Assistant', 'المساعد الذكي'), Icon: Sparkles },
    { id: 'messages', label: t('Chats', 'المحادثات'), Icon: MessageSquare },
  ];

  const staffItems = [
    { id: 'dashboard', label: t('Home', 'الرئيسية'), Icon: Home },
    { id: 'courses', label: t('Courses', 'المقررات'), Icon: BookOpen },
    { id: 'schedule', label: t('Schedule', 'الجدول'), Icon: CalendarDays },
    { id: 'grading', label: t('Grading & Builder', 'التقييم والبناء'), Icon: ClipboardEdit },
    { id: 'assistant', label: t('AI Assistant', 'المساعد الذكي'), Icon: Sparkles },
    { id: 'messages', label: t('Chats', 'المحادثات'), Icon: MessageSquare },
  ];

  const items = role === 'Academic Staff' ? staffItems : studentItems;

  return (
    <nav
      aria-label={t('Floating navigation dock', 'شريط التنقل العائم')}
      className="fixed bottom-4 left-1/2 z-40 flex w-[calc(100%-24px)] max-w-2xl -translate-x-1/2 items-center justify-between gap-1 rounded-[24px] border border-[#E5DCCB] bg-white/95 p-2 shadow-[0_12px_40px_rgba(64,37,12,0.16)] backdrop-blur-xl sm:bottom-5 sm:w-auto sm:gap-1.5 sm:px-3"
    >
      {items.map((item) => {
        const Icon = item.Icon;
        const isCurrent = page === item.id;
        return (
          <button
            key={item.id}
            type="button"
            onClick={() => navigate(item.id)}
            aria-current={isCurrent ? 'page' : undefined}
            className={`flex min-h-[56px] flex-1 flex-col items-center justify-center gap-1 rounded-2xl px-2 py-2 text-[11px] font-semibold transition sm:min-w-[80px] sm:flex-initial sm:px-3 ${
              isCurrent
                ? 'bg-[#FFFACD] text-[#B81104] shadow-[inset_0_0_0_1px_rgba(233,219,169,0.8)]'
                : 'text-[#6E645D] hover:bg-[#FFF9E4] hover:text-[#B81104]'
            }`}
          >
            <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
            <span className="truncate max-w-full leading-tight">{item.label}</span>
          </button>
        );
      })}
    </nav>
  );
}
