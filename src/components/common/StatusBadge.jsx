import React from 'react';
import { CheckCircle2, AlertTriangle, XCircle, Info, Clock } from 'lucide-react';

const STATUS_STYLES = {
  Published: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Approved: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Confirmed: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Active: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  'In Office': { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Available: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Open: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Graded: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Submitted: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },
  Mastered: { bg: 'bg-[#E8F5EC]', text: 'text-[#16845B]', border: 'border-[#16845B]/25', Icon: CheckCircle2 },

  Draft: { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: Clock },
  Pending: { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: Clock },
  'Pending Advisor': { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: Clock },
  'Under Review': { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: Clock },
  Upcoming: { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: Clock },
  Developing: { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: AlertTriangle },
  'Attendance Watch': { bg: 'bg-[#FFF4D4]', text: 'text-[#80540D]', border: 'border-[#B76E00]/25', Icon: AlertTriangle },

  'Needs review': { bg: 'bg-[#FFE9E5]', text: 'text-[#9E1C0E]', border: 'border-[#C93636]/25', Icon: AlertTriangle },
  'Needs Intervention': { bg: 'bg-[#FFE9E5]', text: 'text-[#9E1C0E]', border: 'border-[#C93636]/25', Icon: AlertTriangle },
  Rejected: { bg: 'bg-[#FFE9E5]', text: 'text-[#9E1C0E]', border: 'border-[#C93636]/25', Icon: XCircle },

  Scheduled: { bg: 'bg-[#FFFACD]', text: 'text-[#960D03]', border: 'border-[#E9DBA9]', Icon: Info },
  'In Lecture': { bg: 'bg-[#FFFACD]', text: 'text-[#960D03]', border: 'border-[#E9DBA9]', Icon: Info },
};

export function StatusBadge({ status, label }) {
  const cfg = STATUS_STYLES[status] || {
    bg: 'bg-[#F3EFE6]',
    text: 'text-[#5D514A]',
    border: 'border-[#E8E3D9]',
    Icon: Info,
  };
  const Icon = cfg.Icon;
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap ${cfg.bg} ${cfg.text} ${cfg.border}`}
    >
      <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>{label || status}</span>
    </span>
  );
}
