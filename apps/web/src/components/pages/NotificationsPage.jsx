import React, { useMemo, useState } from 'react';
import { Bell, BellOff, CheckCheck, ExternalLink, Moon, Settings } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';

export function NotificationsPage() {
  const {
    role,
    lang,
    t,
    data,
    prefs,
    unreadCount,
    markAllNotificationsRead,
    markNotificationRead,
    navigate,
  } = useCohort();

  const [filter, setFilter] = useState('all');

  const roleNotifications = useMemo(
    () =>
      data.notifications.filter(
        (n) => !n.forRole || n.forRole === 'All' || n.forRole === role
      ),
    [data.notifications, role]
  );

  const activeNotifications = useMemo(
    () =>
      roleNotifications.filter(
        (n) => !n.prefKey || prefs?.[n.prefKey] !== false
      ),
    [prefs, roleNotifications]
  );

  const mutedNotifications = useMemo(
    () =>
      roleNotifications.filter(
        (n) => n.prefKey && prefs?.[n.prefKey] === false
      ),
    [prefs, roleNotifications]
  );

  const categoryPills = useMemo(() => {
    const base = [
      { id: 'all', label: t(`All (${activeNotifications.length})`, `الكل (${activeNotifications.length})`) },
      { id: 'unread', label: t(`Unread (${unreadCount})`, `غير مقروء (${unreadCount})`) },
    ];
    if (role === 'Academic Staff') {
      return [
        ...base,
        { id: 'submissions', label: t('Submissions', 'التسليمات') },
        { id: 'appeals', label: t('Appeals', 'الالتماسات') },
        { id: 'adviseePetitions', label: t('Petitions', 'طلبات الإرشاد') },
        { id: 'announcements', label: t('Announcements', 'الإعلانات') },
      ];
    }
    return [
      ...base,
      { id: 'assignments', label: t('Assignments', 'التكليفات') },
      { id: 'quizzes', label: t('Quizzes & Exams', 'الاختبارات') },
      { id: 'appointments', label: t('Appointments', 'المواعيد') },
      { id: 'announcements', label: t('Announcements', 'الإعلانات') },
    ];
  }, [activeNotifications.length, role, t, unreadCount]);

  const items = useMemo(() => {
    if (filter === 'all') return activeNotifications;
    if (filter === 'unread') return activeNotifications.filter((n) => !n.read);
    return activeNotifications.filter((n) => n.category === filter || n.prefKey === filter);
  }, [activeNotifications, filter]);

  return (
    <section className="page-enter space-y-5">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <p className="text-[11px] font-bold tracking-widest uppercase text-[#B81104]">
            {t('ACTIVITY & ALERTS', 'التنبيهات والإشعارات')}
          </p>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-[#1A1715]">
            {t('Notifications Center', 'مركز الإشعارات')}
          </h1>
          <p className="text-sm text-[#6E645D] mt-1">
            {t(
              `You have ${unreadCount} unread alert(s) synced with your ${role} notification preferences.`,
              `لديك ${unreadCount} إشعار غير مقروء متزامن مع تفضيلات دور ${role === 'Student' ? 'الطالب' : 'هيئة التدريس'}.`
            )}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => navigate('settings')}
            className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-white border border-[#E5DCCF] text-xs font-bold text-[#1A1715] hover:border-[#B81104]/40"
          >
            <Settings className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
            <span>{t('Preferences', 'التفضيلات')}</span>
          </button>
          <button
            type="button"
            onClick={markAllNotificationsRead}
            className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl bg-[#B81104] text-[#FFFACD] text-xs font-bold hover:bg-[#960D03]"
          >
            <CheckCheck className="w-3.5 h-3.5" aria-hidden="true" />
            <span>{t('Mark All Read', 'تحديد الكل كمقروء')}</span>
          </button>
        </div>
      </div>

      {/* Synced Preferences Rules Status Bar (#10) */}
      <div className="cohort-card rounded-2xl p-3.5 flex flex-wrap items-center justify-between gap-3 text-xs">
        <div className="flex flex-wrap items-center gap-2">
          <span className="rounded-lg bg-[#FCFBF6] border border-[#E8E3D9] px-2.5 py-1 font-semibold text-[#302521]">
            {t('Email Digest:', 'ملخص البريد:')}{' '}
            <strong className={prefs?.emailDigest ? 'text-[#16845B]' : 'text-[#6E645D]'}>
              {prefs?.emailDigest ? t('On', 'مفعّل') : t('Off', 'متوقف')}
            </strong>
          </span>
          <span className="rounded-lg bg-[#FCFBF6] border border-[#E8E3D9] px-2.5 py-1 font-semibold text-[#302521]">
            {t('Push Alerts:', 'التنبيهات الفورية:')}{' '}
            <strong className={prefs?.pushAlerts ? 'text-[#16845B]' : 'text-[#6E645D]'}>
              {prefs?.pushAlerts ? t('On', 'مفعّل') : t('Off', 'متوقف')}
            </strong>
          </span>
          {prefs?.quietStart ? (
            <span className="inline-flex items-center gap-1 rounded-lg bg-[#FFFACD] border border-[#E9DBA9] px-2.5 py-1 font-semibold text-[#302521] tabular-nums">
              <Moon className="h-3.5 w-3.5 text-[#B81104]" aria-hidden="true" />
              <span>
                {t('Quiet after', 'وضع الهدوء بعد')} {prefs.quietStart}
              </span>
            </span>
          ) : null}
        </div>

        {mutedNotifications.length > 0 ? (
          <button
            type="button"
            onClick={() => navigate('settings')}
            className="inline-flex items-center gap-1.5 rounded-lg bg-[#FBF2DC] border border-[#E9DBA9] px-3 py-1 font-bold text-[#960D03] hover:bg-[#FFFACD]"
          >
            <BellOff className="h-3.5 w-3.5" aria-hidden="true" />
            <span>
              {t(
                `${mutedNotifications.length} alert(s) muted by Preferences · Manage`,
                `${mutedNotifications.length} تنبيهات مكتومة من التفضيلات · إدارة`
              )}
            </span>
          </button>
        ) : null}
      </div>

      {/* Category Filter Pills */}
      <div className="flex flex-wrap items-center gap-2">
        {categoryPills.map((tab) => (
          <button
            key={tab.id}
            type="button"
            onClick={() => setFilter(tab.id)}
            className={`px-3.5 py-1.5 rounded-full text-xs font-bold border transition-colors ${
              filter === tab.id
                ? 'bg-[#FFFACD] text-[#960D03] border-[#B81104]'
                : 'bg-white text-[#6E645D] border-[#E5DCCF] hover:border-[#B81104]/40'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="space-y-2.5">
        {items.length === 0 ? (
          <div className="cohort-card rounded-2xl p-8 text-center text-sm text-[#6E645D]">
            {t('No notifications in this filter.', 'لا توجد إشعارات ضمن هذا التصنيف.')}
          </div>
        ) : (
          items.map((n) => (
            <div
              key={n.id}
              className={`cohort-card rounded-2xl p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 ${
                !n.read ? 'border-[#B81104]/40 bg-[#FFFACD]/25' : ''
              }`}
            >
              <div className="flex items-start gap-3">
                <div
                  className={`w-9 h-9 rounded-xl flex items-center justify-center shrink-0 ${
                    !n.read
                      ? 'bg-[#B81104] text-[#FFFACD]'
                      : 'bg-[#F4EFE6] text-[#6E645D]'
                  }`}
                >
                  <Bell className="w-4 h-4" aria-hidden="true" />
                </div>
                <div>
                  <p className="text-sm font-bold text-[#1A1715]">
                    {lang === 'ar' && n.titleAr ? n.titleAr : n.title}
                  </p>
                  {n.detail ? (
                    <p className="text-xs text-[#6E645D] mt-0.5">
                      {lang === 'ar' && n.detailAr ? n.detailAr : n.detail}
                    </p>
                  ) : null}
                  <div className="flex items-center gap-2 text-xs text-[#6E645D] mt-1">
                    <span className="px-2 py-0.5 rounded-full bg-[#F4EFE6] font-semibold">
                      {n.category}
                    </span>
                    <span>{n.time}</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-2 shrink-0">
                {!n.read ? (
                  <button
                    type="button"
                    onClick={() => markNotificationRead(n.id)}
                    className="px-3 py-1.5 rounded-xl bg-white border border-[#E5DCCF] text-xs font-bold text-[#6E645D] hover:text-[#1A1715]"
                  >
                    {t('Mark read', 'مقروء')}
                  </button>
                ) : null}
                <button
                  type="button"
                  onClick={() => {
                    markNotificationRead(n.id);
                    navigate(n.page || 'dashboard', {
                      courseId: n.courseId,
                      courseTab: n.courseTab,
                    });
                  }}
                  className="inline-flex items-center gap-1 px-3 py-1.5 rounded-xl bg-[#B81104]/10 text-[#960D03] text-xs font-bold hover:bg-[#B81104]/20"
                >
                  <ExternalLink className="w-3.5 h-3.5" aria-hidden="true" />
                  <span>{t('Open', 'فتح')}</span>
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </section>
  );
}
