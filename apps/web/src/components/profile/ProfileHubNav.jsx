import React from 'react';
import { User, BarChart3, SlidersHorizontal, ClipboardCheck } from 'lucide-react';
import { useCohort } from '../../context/CohortContext';

export function ProfileHubNav() {
  const { page, navigate, role, t } = useCohort();

  const tabs = [
    { id: 'profile', label: t('Profile Info', 'بيانات الملف'), Icon: User },
    { id: 'academic-affairs', label: t('Academic Affairs (Analytics)', 'الشؤون الأكاديمية والتحليلات'), Icon: BarChart3 },
    { id: 'settings', label: t('Preferences & Notifications', 'التفضيلات والإشعارات'), Icon: SlidersHorizontal },
    {
      id: 'registration',
      label:
        role === 'Student'
          ? t('Course Registration', 'تسجيل المقررات')
          : t('Advisee Approvals', 'اعتماد التسجيل'),
      Icon: ClipboardCheck,
    },
  ];

  return (
    <div
      className="mb-6 flex flex-wrap items-center gap-2 rounded-2xl border border-[#E8E3D9] bg-white p-2"
      role="navigation"
      aria-label={t('Profile Hub Sections', 'أقسام الملف الشخصي')}
    >
      {tabs.map((tab) => {
        const Icon = tab.Icon;
        const active = page === tab.id;
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => navigate(tab.id)}
            aria-current={active ? 'page' : undefined}
            className={`inline-flex min-h-[42px] items-center gap-2 rounded-xl px-4 py-2 text-xs font-semibold transition sm:text-sm ${
              active
                ? 'bg-[#B81104] text-[#FFFACD] shadow-xs'
                : 'text-[#6E645D] hover:bg-[#FFF9E4] hover:text-[#B81104]'
            }`}
          >
            <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
            <span>{tab.label}</span>
          </button>
        );
      })}
    </div>
  );
}
