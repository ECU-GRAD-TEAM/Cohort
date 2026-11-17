import React, { useEffect, useRef, useState } from 'react';
import {
  Search,
  Bell,
  Languages,
  User,
  GraduationCap,
  SlidersHorizontal,
  ClipboardCheck,
  MapPin,
  HelpCircle,
  ChevronDown,
  BarChart3,
  LogOut,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';

export function Header() {
  const {
    role,
    signOut,
    lang,
    toggleLanguage,
    t,
    profile,
    unreadCount,
    page,
    navigate,
    setSearchOpen,
  } = useCohort();

  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);
  const displayName = lang === 'ar' && profile.nameAr ? profile.nameAr : profile.name;
  const initials = profile.name
    .split(' ')
    .filter(Boolean)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  useEffect(() => {
    const onPointerDown = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setMenuOpen(false);
      }
    };
    const onKeyDown = (e) => {
      if (e.key === 'Escape') setMenuOpen(false);
    };
    document.addEventListener('mousedown', onPointerDown);
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('mousedown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown);
    };
  }, []);

  const profileMenuItems = [
    {
      id: 'profile',
      label: t('My Profile', 'الملف الشخصي'),
      desc: t('Display name, phone & academic record', 'الاسم والهاتف والبيانات الأكاديمية'),
      Icon: User,
    },
    {
      id: 'academic-affairs',
      label: t('Academic Affairs & Analytics', 'الشؤون الأكاديمية والتحليلات'),
      desc:
        role === 'Student'
          ? t('GPA trends, attendance & petitions', 'المعدل التراكمي والحضور والالتماسات')
          : t('Cohort analytics, mastery & advisees', 'تحليلات الدفعة ومستوى الإتقان والمرشدين'),
      Icon: BarChart3,
      highlight: true,
    },
    {
      id: 'registration',
      label:
        role === 'Student'
          ? t('Course Registration', 'تسجيل المقررات')
          : t('Advisee Approvals & Rosters', 'اعتماد تسجيل الطلاب والقوائم'),
      desc:
        role === 'Student'
          ? t('Your courses, sections & class times', 'مقرراتك وشعبك ومواعيدك')
          : t('Lecture, Lab & Section scheduling', 'المحاضرات والمعامل والسكاشن'),
      Icon: ClipboardCheck,
    },
    {
      id: 'map',
      label: t('Campus Map & Rooms', 'خريطة الجامعة والغرف'),
      desc: t('Labs, halls, TA rooms & admins', 'المعامل والقاعات وغرف المعيدين والإدارة'),
      Icon: MapPin,
    },
    {
      id: 'settings',
      label: t('Preferences & Notifications', 'التفضيلات والإشعارات'),
      desc: t('Alerts, quiet hours, RTL & motion', 'التنبيهات وأوقات الهدوء واللغة'),
      Icon: SlidersHorizontal,
    },
    {
      id: 'support',
      label: t('Help & Support', 'الدعم والمساعدة'),
      desc: t('Requests & campus desk', 'الطلبات ومكتب الدعم'),
      Icon: HelpCircle,
    },
  ];

  return (
    <header className="sticky top-0 z-40 border-b border-[#E8E3D9] bg-white/95 backdrop-blur-md">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:start-3 focus:z-50 focus:rounded-lg focus:bg-[#B81104] focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-white"
      >
        {t('Skip to main content', 'تخطي إلى المحتوى الرئيسي')}
      </a>

      <div className="mx-auto flex max-w-[1520px] flex-wrap items-center justify-between gap-3 px-4 py-3 sm:px-6 lg:px-8">
        {/* Brand Logo */}
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => navigate('dashboard')}
            className="flex items-center gap-2.5 rounded-xl px-1 py-1 text-start transition hover:opacity-90"
            aria-label={t('Cohort Home', 'الصفحة الرئيسية - Cohort')}
          >
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-[#B81104] text-lg font-extrabold text-[#FFFACD] shadow-sm">
              C
            </span>
            <span className="flex flex-col">
              <span className="text-xl font-extrabold tracking-tight text-[#302521] leading-none">
                Co<span className="text-[#B81104]">hort</span>
              </span>
              <span className="mt-0.5 text-[10px] font-semibold tracking-wider text-[#6E645D] uppercase">
                {role === 'Student'
                  ? t('Student Portal', 'بوابة الطالب')
                  : t('Academic Staff Portal', 'بوابة هيئة التدريس')}
              </span>
            </span>
          </button>
        </div>

        {/* Categorized Global Search Trigger (#6) */}
        <div className="order-3 w-full md:order-2 md:w-auto md:flex-1 md:max-w-md lg:max-w-lg">
          <button
            type="button"
            onClick={() => setSearchOpen(true)}
            className="flex w-full items-center justify-between gap-2 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] px-3.5 py-2.5 text-sm text-[#6E645D] transition hover:border-[#B81104]/50 hover:bg-white"
            aria-label={t(
              'Search students, academic staff, lecturers, administrators, courses or labs',
              'ابحث عن الطلاب أو هيئة التدريس أو الإداريين أو المقررات أو المعامل'
            )}
          >
            <span className="flex items-center gap-2 truncate">
              <Search className="h-4 w-4 shrink-0 text-[#B81104]" aria-hidden="true" />
              <span className="truncate">
                {t(
                  'Search students, lecturers, TAs, admins, courses…',
                  'ابحث عن طالب، محاضر، معيد، إداري، مقرر…'
                )}
              </span>
            </span>
            <kbd className="hidden rounded border border-[#E8E3D9] bg-white px-1.5 py-0.5 text-[11px] font-semibold text-[#6E645D] sm:inline-block">
              /
            </kbd>
          </button>
        </div>

        {/* Role Switcher, Language Toggle, Notifications & Profile Hub Menu */}
        <div className="order-2 flex items-center gap-2 sm:gap-3 md:order-3">
          {/* Workspace: set by the account's role at the university, not chosen here */}
          <div className="hidden items-center gap-1.5 rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] px-2.5 py-2 sm:flex">
            <GraduationCap className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
            <span className="text-xs font-semibold text-[#302521] sm:text-sm">
              {role === 'Student' ? t('Student', 'طالب') : t('Academic Staff', 'هيئة التدريس')}
            </span>
          </div>

          {/* Language Toggle */}
          <button
            type="button"
            onClick={toggleLanguage}
            className="inline-flex min-h-[40px] items-center gap-1.5 rounded-xl border border-[#E8E3D9] bg-white px-3 py-1.5 text-xs font-semibold text-[#302521] transition hover:border-[#B81104]/50 hover:bg-[#FFF9E4]"
            aria-label={t('Switch language to Arabic', 'تبديل اللغة إلى الإنجليزية')}
          >
            <Languages className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
            <span>{lang === 'ar' ? 'English' : 'العربية'}</span>
          </button>

          {/* Notifications Button */}
          <button
            type="button"
            onClick={() => navigate('notifications')}
            className={`relative grid h-10 w-10 place-items-center rounded-xl border transition ${
              page === 'notifications'
                ? 'border-[#B81104] bg-[#FFFACD] text-[#B81104]'
                : 'border-[#E8E3D9] bg-white text-[#302521] hover:bg-[#FFF9E4]'
            }`}
            aria-label={t(
              `Notifications (${unreadCount} unread)`,
              `الإشعارات (${unreadCount} غير مقروء)`
            )}
          >
            <Bell className="h-4 w-4" aria-hidden="true" />
            {unreadCount > 0 ? (
              <span className="absolute -top-1 -end-1 grid h-4 min-w-[16px] place-items-center rounded-full bg-[#B81104] px-1 text-[10px] font-bold text-white">
                {unreadCount}
              </span>
            ) : null}
          </button>

          {/* Profile Menu Dropdown (Houses Profile, Academic Affairs, Registration, Map, Preferences) */}
          <div className="relative" ref={menuRef}>
            <button
              type="button"
              onClick={() => setMenuOpen((prev) => !prev)}
              aria-haspopup="menu"
              aria-expanded={menuOpen}
              aria-label={t('Open profile and academic affairs menu', 'فتح قائمة الملف الشخصي والشؤون الأكاديمية')}
              className="flex min-h-[42px] items-center gap-2 rounded-full border border-[#E8E3D9] bg-white p-1 pe-2.5 transition hover:border-[#B81104]/60 hover:bg-[#FFF9E4]"
            >
              <span className="grid h-8 w-8 place-items-center rounded-full bg-[#B81104] text-xs font-bold text-[#FFFACD]">
                {initials}
              </span>
              <span className="hidden max-w-[120px] truncate text-xs font-semibold text-[#302521] lg:inline">
                {displayName}
              </span>
              <ChevronDown
                className={`h-3.5 w-3.5 text-[#6E645D] transition-transform ${menuOpen ? 'rotate-180' : ''}`}
                aria-hidden="true"
              />
            </button>

            {menuOpen ? (
              <div
                role="menu"
                aria-label={t('Profile & Academic Affairs Menu', 'قائمة الملف والشؤون الأكاديمية')}
                className="absolute end-0 top-[calc(100%+8px)] z-50 w-72 rounded-2xl border border-[#E8E3D9] bg-white p-2 shadow-xl"
              >
                <div className="mb-1.5 border-b border-[#E8E3D9] px-3 py-2.5">
                  <div className="flex items-center justify-between gap-2">
                    <p className="truncate text-sm font-bold text-[#302521]">{displayName}</p>
                    {profile.id ? (
                      <span className="rounded-md bg-[#FFFACD] px-2 py-0.5 text-[10px] font-bold text-[#B81104]">
                        {profile.id}
                      </span>
                    ) : null}
                  </div>
                  <p className="mt-0.5 truncate text-xs text-[#6E645D]">{profile.email}</p>
                </div>

                <div className="space-y-1">
                  {profileMenuItems.map((item) => {
                    const Icon = item.Icon;
                    const active = page === item.id;
                    return (
                      <button
                        key={item.id}
                        type="button"
                        role="menuitem"
                        onClick={() => {
                          setMenuOpen(false);
                          navigate(item.id);
                        }}
                        className={`flex w-full items-start gap-3 rounded-xl px-3 py-2.5 text-start transition ${
                          active
                            ? 'bg-[#FFFACD] text-[#B81104]'
                            : item.highlight
                              ? 'bg-[#FFF9E4]/60 text-[#302521] hover:bg-[#FFFACD]'
                              : 'text-[#302521] hover:bg-[#FCFBF6]'
                        }`}
                      >
                        <span
                          className={`mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-lg ${
                            active || item.highlight
                              ? 'bg-[#B81104] text-[#FFFACD]'
                              : 'bg-[#FCFBF6] text-[#B81104] border border-[#E8E3D9]'
                          }`}
                        >
                          <Icon className="h-4 w-4" aria-hidden="true" />
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="flex items-center justify-between gap-2 text-xs font-bold">
                            <span>{item.label}</span>
                            {item.highlight ? (
                              <span className="rounded bg-[#B81104]/10 px-1.5 py-0.5 text-[9px] font-bold text-[#B81104]">
                                {t('Analytics', 'تحليلات')}
                              </span>
                            ) : null}
                          </span>
                          <span className="mt-0.5 block truncate text-[11px] text-[#6E645D]">
                            {item.desc}
                          </span>
                        </span>
                      </button>
                    );
                  })}
                </div>

                <div className="mt-1.5 border-t border-[#E8E3D9] pt-1.5">
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      setMenuOpen(false);
                      signOut();
                    }}
                    className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-start text-xs font-bold text-[#302521] transition hover:bg-[#FCFBF6]"
                  >
                    <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg border border-[#E8E3D9] bg-[#FCFBF6] text-[#B81104]">
                      <LogOut className="h-4 w-4" aria-hidden="true" />
                    </span>
                    {t('Sign out', 'تسجيل الخروج')}
                  </button>
                </div>
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </header>
  );
}
