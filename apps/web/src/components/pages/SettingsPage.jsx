import React from 'react';
import { Bell, Download, Globe, Moon, Shield, Sparkles } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { ProfileHubNav } from '../profile/ProfileHubNav';

export function SettingsPage() {
  const { role, lang, toggleLanguage, t, prefs, updatePrefs, exportWorkspaceData } = useCohort();

  const notificationCategories =
    role === 'Student'
      ? [
          {
            key: 'assignments',
            title: t('Assignments & Deadlines', 'التكليفات والمواعيد النهائية'),
            desc: t('New assignments, reminders 24h before due dates, and grading release.', 'التكليفات الجديدة والتذكيرات قبل الموعد وإتاحة الدرجات.'),
          },
          {
            key: 'quizzes',
            title: t('Quizzes & Timed Assessments', 'الاختبارات القصيرة والتقييمات'),
            desc: t('Quiz opening windows, attempt confirmations, and appeal outcomes.', 'مواعيد فتح الاختبارات وتأكيد المحاولات ونتائج الالتماسات.'),
          },
          {
            key: 'exams',
            title: t('Exam Schedules & Seat Releases', 'جداول الامتحانات وأرقام الجلوس'),
            desc: t('Hall assignments, seat numbers, and exam day notices.', 'توزيع اللجان وأرقام الجلوس وتنبيهات الامتحانات.'),
          },
          {
            key: 'announcements',
            title: t('Course & University Announcements', 'إعلانات المقررات والجامعة'),
            desc: t('Policy updates, registration windows, and instructor notices.', 'تحديثات اللوائح وفترات التسجيل وإعلانات المحاضرين.'),
          },
          {
            key: 'chats',
            title: t('Academic Advisor & Course Chats', 'محادثات المرشد والمقررات'),
            desc: t('Direct messages from your advisor, lecturers, TAs, and course groups.', 'الرسائل المباشرة من المرشد وهيئة التدريس ومجموعات المقررات.'),
          },
          {
            key: 'appointments',
            title: t('Office-Hour Appointments', 'مواعيد الساعات المكتبية'),
            desc: t('Booking confirmations, reschedules, and session reminders.', 'تأكيد الحجوزات وتعديلات المواعيد والتذكيرات.'),
          },
        ]
      : [
          {
            key: 'submissions',
            title: t('Student Assignment Submissions', 'تسليمات تكليفات الطلاب'),
            desc: t('Notifications when students upload lab work or resubmit before deadline.', 'تنبيهات عند تسليم الطلاب أو إعادة التسليم.'),
          },
          {
            key: 'appeals',
            title: t('Quiz Appeals & Manual Reviews', 'التماسات الاختبارات والمراجعة اليدوية'),
            desc: t('Written answer grading queues and student grade appeal alerts.', 'قوائم تصحيح الأسئلة المقالية والتماسات الدرجات.'),
          },
          {
            key: 'adviseePetitions',
            title: t('Advisee Registration & Petitions', 'تسجيل الطلاب والالتماسات الأكاديمية'),
            desc: t('Overload requests, prerequisite overrides, and add/drop petitions.', 'طلبات زيادة العبء وتجاوز المتطلبات والتعديل.'),
          },
          {
            key: 'appointments',
            title: t('Office-Hour Bookings', 'حجوزات الساعات المكتبية'),
            desc: t('New student appointments and cancellation alerts.', 'حجوزات الطلاب الجديدة وإلغاء المواعيد.'),
          },
          {
            key: 'announcements',
            title: t('Department & Institutional Notices', 'إشعارات القسم والجامعة'),
            desc: t('Grading deadlines, registrar calendars, and faculty memos.', 'مواعيد رصد الدرجات والتقويم الأكاديمي.'),
          },
          {
            key: 'chats',
            title: t('Course Discussions & Direct Chats', 'مناقشات المقررات والمحادثات المباشرة'),
            desc: t('Messages from advisees, TAs, colleagues, and course channels.', 'رسائل الطلاب والمعيدين والزملاء وقنوات المقررات.'),
          },
        ];

  return (
    <section className="page-enter space-y-6">
      <div>
        <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
          {t('PREFERENCES & SETTINGS', 'التفضيلات والإعدادات')}
        </p>
        <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
          {t('Notifications & Workspace Preferences', 'تفضيلات الإشعارات ومساحة العمل')}
        </h1>
        <p className="mt-1 text-sm text-[#6E645D]">
          {t(
            'Tailor which alerts reach you, configure quiet hours, and manage bilingual accessibility settings.',
            'خصّص التنبيهات التي تصلك واضبط أوقات الهدوء وإعدادات اللغة وسهولة الوصول.'
          )}
        </p>
      </div>

      <ProfileHubNav />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        {/* Notification Controls (#10) */}
        <div className="cohort-card p-6 lg:col-span-7 space-y-5">
          <div className="flex items-center gap-2.5 border-b border-[#E8E3D9] pb-4">
            <span className="grid h-10 w-10 place-items-center rounded-xl bg-[#FFFACD] text-[#B81104]">
              <Bell className="h-5 w-5" aria-hidden="true" />
            </span>
            <div>
              <h2 className="text-base font-bold text-[#302521]">
                {t('Notification Channels & Categories', 'قنوات وفئات الإشعارات')}
              </h2>
              <p className="text-xs text-[#6E645D]">
                {role === 'Student'
                  ? t('Configured for Student alerts', 'مُهيأة لتنبيهات الطالب')
                  : t('Configured for Academic Staff workflows', 'مُهيأة لسير عمل هيئة التدريس')}
              </p>
            </div>
          </div>

          <div className="divide-y divide-[#E8E3D9]">
            {notificationCategories.map((item) => {
              const checked = prefs[item.key] !== false;
              const inputId = `pref-${item.key}`;
              return (
                <label
                  key={item.key}
                  htmlFor={inputId}
                  className="flex cursor-pointer items-start justify-between gap-4 py-4 first:pt-1 last:pb-1"
                >
                  <div>
                    <span className="block text-sm font-semibold text-[#302521]">{item.title}</span>
                    <span className="mt-0.5 block text-xs text-[#6E645D]">{item.desc}</span>
                  </div>
                  <input
                    id={inputId}
                    type="checkbox"
                    checked={checked}
                    onChange={(e) => updatePrefs({ [item.key]: e.target.checked })}
                    className="mt-1 h-5 w-5 shrink-0 rounded accent-[#B81104]"
                  />
                </label>
              );
            })}
          </div>

          <div className="grid grid-cols-1 gap-4 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-4 sm:grid-cols-3">
            <label className="flex items-center gap-2.5 text-xs font-semibold text-[#302521] cursor-pointer">
              <input
                type="checkbox"
                checked={Boolean(prefs.emailDigest)}
                onChange={(e) => updatePrefs({ emailDigest: e.target.checked })}
                className="h-4 w-4 accent-[#B81104]"
              />
              <span>{t('Email Digest', 'ملخص البريد')}</span>
            </label>

            <label className="flex items-center gap-2.5 text-xs font-semibold text-[#302521] cursor-pointer">
              <input
                type="checkbox"
                checked={Boolean(prefs.pushAlerts)}
                onChange={(e) => updatePrefs({ pushAlerts: e.target.checked })}
                className="h-4 w-4 accent-[#B81104]"
              />
              <span>{t('Browser Push', 'إشعارات المتصفح')}</span>
            </label>

            <div className="flex items-center justify-between gap-2 sm:justify-end">
              <label htmlFor="quiet-hours-input" className="flex items-center gap-1 text-xs font-semibold text-[#302521]">
                <Moon className="h-3.5 w-3.5 text-[#B81104]" aria-hidden="true" />
                <span>{t('Quiet after', 'هدوء بعد')}</span>
              </label>
              <input
                id="quiet-hours-input"
                type="time"
                value={prefs.quietStart || '22:00'}
                onChange={(e) => updatePrefs({ quietStart: e.target.value })}
                className="rounded-lg border border-[#D6CFC1] bg-white px-2 py-1 text-xs font-semibold text-[#302521]"
              />
            </div>
          </div>
        </div>

        {/* Language, Accessibility & Data Controls */}
        <div className="space-y-6 lg:col-span-5">
          <div className="cohort-card p-6 space-y-4">
            <div className="flex items-center gap-2.5">
              <span className="grid h-9 w-9 place-items-center rounded-xl bg-[#FFFACD] text-[#B81104]">
                <Globe className="h-4 w-4" aria-hidden="true" />
              </span>
              <div>
                <h2 className="text-base font-bold text-[#302521]">
                  {t('Language & Accessibility', 'اللغة وسهولة الوصول')}
                </h2>
                <p className="text-xs text-[#6E645D]">
                  {t('Full LTR/RTL layout and motion controls', 'تبديل كامل للاتجاه والتحكم في الحركة')}
                </p>
              </div>
            </div>

            <div className="flex items-center justify-between rounded-xl border border-[#E8E3D9] p-4">
              <div>
                <p className="text-sm font-semibold text-[#302521]">
                  {t('Interface Language', 'لغة الواجهة')}
                </p>
                <p className="text-xs text-[#6E645D]">
                  {lang === 'ar' ? 'العربية (اتجاه من اليمين لليسار)' : 'English (Left-to-Right)'}
                </p>
              </div>
              <button
                type="button"
                onClick={toggleLanguage}
                className="min-h-[40px] rounded-xl bg-[#B81104] px-4 py-2 text-xs font-bold text-white hover:bg-[#940E03]"
              >
                {lang === 'ar' ? 'Switch to English' : 'التبديل للعربية'}
              </button>
            </div>

            <label
              htmlFor="reduce-motion-toggle"
              className="flex cursor-pointer items-center justify-between rounded-xl border border-[#E8E3D9] p-4"
            >
              <div>
                <span className="flex items-center gap-1.5 text-sm font-semibold text-[#302521]">
                  <Sparkles className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                  {t('Reduce Motion', 'تقليل الحركة والتأثيرات')}
                </span>
                <span className="mt-0.5 block text-xs text-[#6E645D]">
                  {t('Minimizes page transitions for vestibular comfort.', 'يقلل حركات الانتقال لراحة العين.')}
                </span>
              </div>
              <input
                id="reduce-motion-toggle"
                type="checkbox"
                checked={Boolean(prefs.reduceMotion)}
                onChange={(e) => updatePrefs({ reduceMotion: e.target.checked })}
                className="h-5 w-5 shrink-0 accent-[#B81104]"
              />
            </label>
          </div>

          <div className="cohort-card p-6 space-y-3">
            <div className="flex items-center gap-2">
              <Shield className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
              <h2 className="text-base font-bold text-[#302521]">
                {t('Workspace Data & Privacy', 'بيانات مساحة العمل والخصوصية')}
              </h2>
            </div>
            <p className="text-xs leading-relaxed text-[#6E645D]">
              {t(
                'All profile updates, course registrations, and preferences are currently stored locally in your browser during UI development.',
                'جميع التعديلات والتسجيلات والتفضيلات محفوظة محليًا في المتصفح حاليًا أثناء تصميم الواجهات.'
              )}
            </p>
            <button
              type="button"
              onClick={exportWorkspaceData}
              className="inline-flex min-h-[42px] items-center gap-2 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] px-4 py-2 text-xs font-bold text-[#302521] hover:border-[#B81104] hover:text-[#B81104]"
            >
              <Download className="h-4 w-4" aria-hidden="true" />
              <span>{t('Export Workspace Snapshot (JSON)', 'تصدير نسخة البيانات (JSON)')}</span>
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
