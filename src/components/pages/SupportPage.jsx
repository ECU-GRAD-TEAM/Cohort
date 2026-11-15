import React, { useState } from 'react';
import { HelpCircle, LifeBuoy, MapPin, Send } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { StatusBadge } from '../common/StatusBadge';

const DEFAULT_TICKETS = [
  {
    id: 'sup-1',
    category: 'Academic Advising',
    subject: 'Prerequisite waiver confirmation for CS330',
    status: 'Under Review',
    date: '2026-11-13',
  },
];

export function SupportPage() {
  const { role, t, data, setData, navigate, showToast } = useCohort();
  const [category, setCategory] = useState('Academic Advising');
  const [subject, setSubject] = useState('');
  const [details, setDetails] = useState('');

  const tickets = data.supportTickets || DEFAULT_TICKETS;
  const isStaff = role === 'Academic Staff';

  const handleUpdateTicketStatus = (ticketId, nextStatus) => {
    setData((prev) => ({
      ...prev,
      supportTickets: (prev.supportTickets || DEFAULT_TICKETS).map((tk) =>
        tk.id === ticketId ? { ...tk, status: nextStatus } : tk
      ),
    }));
    showToast(t(`Ticket updated to ${nextStatus}.`, `تم تحديث حالة الطلب إلى ${nextStatus}.`));
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!subject.trim() || !details.trim()) {
      showToast(t('Please enter ticket subject and details', 'يرجى إدخال عنوان وتفاصيل الطلب'));
      return;
    }
    const newTicket = {
      id: `sup-${Date.now()}`,
      category,
      subject: subject.trim(),
      details: details.trim(),
      status: 'Pending Advisor',
      date: new Date().toISOString().slice(0, 10),
    };
    setData((prev) => ({
      ...prev,
      supportTickets: [newTicket, ...(prev.supportTickets || DEFAULT_TICKETS)],
    }));
    setSubject('');
    setDetails('');
    showToast(t('Support request submitted', 'تم إرسال طلب الدعم بنجاح'));
  };

  return (
    <section className="page-enter space-y-6">
      <div className="cohort-card bg-white rounded-3xl p-6 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <p className="text-[11px] font-bold tracking-widest uppercase text-[#B81104]">
            {t('HELP & ACADEMIC SUPPORT', 'المساعدة والدعم الأكاديمي')}
          </p>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-[#1A1715] mt-1">
            {t('Student & Staff Support Desk', 'مكتب دعم الطلاب وهيئة التدريس')}
          </h1>
          <p className="text-sm text-[#6E645D] mt-1">
            {role === 'Student'
              ? t(
                  'Contact Student Affairs, Registrar desk, or technical support.',
                  'تواصل مع شؤون الطلاب أو مكتب التسجيل أو الدعم الفني.'
                )
              : t(
                  'Submit faculty classroom IT, grading portal, or department logistics tickets.',
                  'إرسال طلبات دعم القاعات الدراسية أو نظام الدرجات.'
                )}
          </p>
        </div>

        <button
          type="button"
          onClick={() => navigate('map')}
          className="self-start inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white border border-[#E5DCCF] text-xs font-bold text-[#1A1715] hover:border-[#B81104]"
        >
          <MapPin className="w-4 h-4 text-[#B81104]" />
          {t('Find Admin Offices on Map', 'مواقع المكاتب على الخريطة')}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-5">
        <form onSubmit={handleSubmit} className="lg:col-span-7 cohort-card rounded-2xl p-5 space-y-4">
          <div className="flex items-center gap-2">
            <LifeBuoy className="w-5 h-5 text-[#B81104]" />
            <h2 className="text-base font-extrabold text-[#1A1715]">
              {t('Submit New Support Ticket', 'فتح تذكرة دعم جديدة')}
            </h2>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-bold text-[#6E645D] mb-1">
                {t('Department / Category', 'القسم المختص')}
              </label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full rounded-xl border border-[#E5DCCF] bg-white px-3 py-2 text-sm"
              >
                <option value="Academic Advising">{t('Academic Advising', 'الإرشاد الأكاديمي')}</option>
                <option value="Registrar & Registration">{t('Registrar & Registration', 'التسجيل وشؤون الخريجين')}</option>
                <option value="Lab & Room Facilities">{t('Lab & Room Facilities', 'المعامل والقاعات الدراسية')}</option>
                <option value="Portal & Accessibility">{t('Portal & Accessibility', 'البوابة وسهولة الوصول')}</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-bold text-[#6E645D] mb-1">
                {t('Subject', 'الموضوع')}
              </label>
              <input
                type="text"
                value={subject}
                onChange={(e) => setSubject(e.target.value)}
                placeholder={t('Short summary of your request', 'ملخص مختصر للطلب')}
                className="w-full rounded-xl border border-[#E5DCCF] bg-white px-3 py-2 text-sm"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-bold text-[#6E645D] mb-1">
              {t('Details', 'التفاصيل')}
            </label>
            <textarea
              rows={3}
              value={details}
              onChange={(e) => setDetails(e.target.value)}
              placeholder={t(
                'Include course code, lab room, or petition ID if relevant...',
                'اذكر رمز المقرر أو رقم المعمل أو الطلب إن وجد...'
              )}
              className="w-full rounded-xl border border-[#E5DCCF] bg-white px-3 py-2 text-sm"
            />
          </div>

          <button
            type="submit"
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-[#B81104] text-[#FFFACD] text-sm font-bold hover:bg-[#960D03]"
          >
            <Send className="w-4 h-4" />
            {t('Submit Ticket', 'إرسال الطلب')}
          </button>
        </form>

        <div className="lg:col-span-5 cohort-card rounded-2xl p-5 space-y-3">
          <div className="flex items-center gap-2">
            <HelpCircle className="w-5 h-5 text-[#B81104]" />
            <h2 className="text-base font-extrabold text-[#1A1715]">
              {t('Recent Requests', 'الطلبات السابقة')}
            </h2>
          </div>

          <div className="space-y-2.5">
            {tickets.map((tk) => (
              <div
                key={tk.id}
                className="rounded-xl border border-[#E5DCCF] bg-[#FDFBF7] p-3.5 space-y-1.5"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="text-xs font-bold text-[#960D03]">{tk.category}</span>
                  <StatusBadge status={tk.status} />
                </div>
                <p className="text-sm font-bold text-[#1A1715]">{tk.subject}</p>
                {tk.details ? <p className="text-xs text-[#6E645D]">{tk.details}</p> : null}
                <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
                  <p className="text-[11px] text-[#6E645D] tabular-nums">{tk.date}</p>
                  {isStaff && tk.status !== 'Resolved' ? (
                    <div className="flex items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => handleUpdateTicketStatus(tk.id, 'Resolved')}
                        className="rounded-lg bg-[#16845B] px-2.5 py-1 text-[11px] font-bold text-white hover:opacity-90"
                      >
                        {t('Mark Resolved', 'إغلاق كمحلول')}
                      </button>
                    </div>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
