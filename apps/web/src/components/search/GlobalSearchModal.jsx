import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Search,
  X,
  MessageSquare,
  MapPin,
  BookOpen,
  Users,
  ShieldCheck,
  GraduationCap,
  Building2,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { CAMPUS_LOCATIONS, DIRECTORY_PEOPLE } from '../../data/seedData';
import { StatusBadge } from '../common/StatusBadge';

export function GlobalSearchModal() {
  const { searchOpen, setSearchOpen, searchQuery, setSearchQuery, data, lang, t, navigate, role } =
    useCohort();
  const [category, setCategory] = useState('All');
  const inputRef = useRef(null);

  useEffect(() => {
    if (searchOpen) {
      setTimeout(() => inputRef.current?.focus(), 30);
    }
  }, [searchOpen]);

  const categories = [
    { id: 'All', label: t('All', 'الكل') },
    { id: 'Student', label: t('Students', 'الطلاب') },
    { id: 'Academic Staff', label: t('Lecturers & TAs', 'المحاضرون والمعيدون') },
    { id: 'Administrator', label: t('Administrators', 'الإداريون') },
    { id: 'Courses', label: t('Courses', 'المقررات') },
    { id: 'Locations', label: t('Labs & Rooms', 'المعامل والقاعات') },
  ];

  const results = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    const list = [];

    if (category === 'All' || ['Student', 'Academic Staff', 'Administrator'].includes(category)) {
      DIRECTORY_PEOPLE.forEach((p) => {
        if (category !== 'All' && p.category !== category) return;
        const hay = `${p.name} ${p.nameAr} ${p.subRole} ${p.subRoleAr} ${p.department} ${p.room} ${p.email}`.toLowerCase();
        if (!q || hay.includes(q)) {
          list.push({ kind: 'person', item: p });
        }
      });
    }

    if (category === 'All' || category === 'Courses') {
      data.courses.forEach((c) => {
        const hay = `${c.id} ${c.name} ${c.nameAr} ${c.teacher} ${c.ta} ${c.topic}`.toLowerCase();
        if (!q || hay.includes(q)) {
          list.push({ kind: 'course', item: c });
        }
      });
    }

    if (category === 'All' || category === 'Locations') {
      CAMPUS_LOCATIONS.forEach((loc) => {
        const hay = `${loc.name} ${loc.nameAr} ${loc.category} ${loc.zone} ${loc.rooms.join(' ')}`.toLowerCase();
        if (!q || hay.includes(q)) {
          list.push({ kind: 'location', item: loc });
        }
      });
    }

    return list;
  }, [category, data.courses, searchQuery]);

  if (!searchOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-[#302521]/45 p-4 pt-12 backdrop-blur-xs sm:pt-20"
      role="dialog"
      aria-modal="true"
      aria-label={t('Global Directory & Campus Search', 'البحث الشامل في الجامعة')}
      onClick={(e) => {
        if (e.target === e.currentTarget) setSearchOpen(false);
      }}
    >
      <div className="w-full max-w-3xl overflow-hidden rounded-2xl border border-[#E8E3D9] bg-white shadow-2xl">
        {/* Search Header */}
        <div className="flex items-center gap-3 border-b border-[#E8E3D9] bg-[#FCFBF6] px-4 py-3.5">
          <Search className="h-5 w-5 shrink-0 text-[#B81104]" aria-hidden="true" />
          <input
            ref={inputRef}
            type="search"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder={t(
              'Search by name, student ID, lecturer, TA room, administrator, course or lab…',
              'ابحث بالاسم، الرقم الجامعي، المحاضر، غرفة المعيد، الإداري، المقرر أو المعمل…'
            )}
            className="w-full bg-transparent text-sm text-[#302521] placeholder:text-[#6E645D] focus:outline-none"
            aria-label={t('Global search input', 'حقل البحث الشامل')}
          />
          <button
            type="button"
            onClick={() => setSearchOpen(false)}
            className="grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-[#E8E3D9] bg-white text-[#6E645D] hover:text-[#B81104]"
            aria-label={t('Close search', 'إغلاق البحث')}
          >
            <X className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>

        {/* Category Chips */}
        <div className="flex flex-wrap items-center gap-2 border-b border-[#E8E3D9] bg-white px-4 py-3">
          {categories.map((cat) => (
            <button
              key={cat.id}
              type="button"
              onClick={() => setCategory(cat.id)}
              className={`rounded-lg border px-3 py-1.5 text-xs font-semibold transition ${
                category === cat.id
                  ? 'border-[#B81104] bg-[#B81104] text-white'
                  : 'border-[#E8E3D9] bg-[#FCFBF6] text-[#302521] hover:border-[#B81104]/50'
              }`}
            >
              {cat.label}
            </button>
          ))}
        </div>

        {/* Results */}
        <div className="max-h-[60vh] divide-y divide-[#E8E3D9] overflow-y-auto p-2">
          {results.length === 0 ? (
            <div className="py-12 text-center text-sm text-[#6E645D]">
              {t('No matching records found.', 'لا توجد نتائج مطابقة للبحث.')}
            </div>
          ) : (
            results.map((entry, idx) => {
              if (entry.kind === 'person') {
                const p = entry.item;
                const Icon =
                  p.category === 'Student'
                    ? Users
                    : p.category === 'Administrator'
                      ? ShieldCheck
                      : GraduationCap;
                const title = lang === 'ar' ? p.nameAr : p.name;
                const subtitle = lang === 'ar' ? p.subRoleAr : p.subRole;
                return (
                  <div
                    key={`${p.id}-${idx}`}
                    className="flex flex-col justify-between gap-3 rounded-xl p-3 transition hover:bg-[#FCFBF6] sm:flex-row sm:items-center"
                  >
                    <div className="flex items-start gap-3">
                      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-[#FFFACD] text-[#B81104]">
                        <Icon className="h-5 w-5" aria-hidden="true" />
                      </span>
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <h3 className="text-sm font-bold text-[#302521]">{title}</h3>
                          <StatusBadge status={p.status} label={lang === 'ar' ? p.statusAr : p.status} />
                        </div>
                        <p className="mt-0.5 text-xs text-[#6E645D]">
                          {subtitle} · {p.room}
                        </p>
                        {p.officeHours ? (
                          <p className="mt-0.5 text-[11px] font-medium text-[#B81104]">
                            {t('Office Hours:', 'الساعات المكتبية:')} {p.officeHours}
                          </p>
                        ) : null}
                      </div>
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                      <button
                        type="button"
                        onClick={() =>
                          navigate('messages', {
                            chatThread: p.isAdvisor ? 'advisor-leila' : `direct-${p.id}`,
                          })
                        }
                        className="inline-flex min-h-[36px] items-center gap-1.5 rounded-lg border border-[#E8E3D9] bg-white px-3 py-1.5 text-xs font-semibold text-[#302521] hover:border-[#B81104] hover:text-[#B81104]"
                      >
                        <MessageSquare className="h-3.5 w-3.5" aria-hidden="true" />
                        <span>{t('Chat', 'محادثة')}</span>
                      </button>
                      {p.category !== 'Student' ? (
                        <button
                          type="button"
                          onClick={() => navigate('map', { buildingId: p.buildingId })}
                          className="inline-flex min-h-[36px] items-center gap-1.5 rounded-lg bg-[#FFFACD] px-3 py-1.5 text-xs font-semibold text-[#B81104] hover:bg-[#FFF2B5]"
                        >
                          <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                          <span>{t('Locate Room', 'تحديد الغرفة')}</span>
                        </button>
                      ) : role === 'Academic Staff' ? (
                        <button
                          type="button"
                          onClick={() => navigate('academic-affairs')}
                          className="inline-flex min-h-[36px] items-center gap-1.5 rounded-lg bg-[#FFFACD] px-3 py-1.5 text-xs font-semibold text-[#B81104]"
                        >
                          <span>{t('Advisee Analytics', 'تحليلات الطالب')}</span>
                        </button>
                      ) : null}
                    </div>
                  </div>
                );
              }

              if (entry.kind === 'course') {
                const c = entry.item;
                return (
                  <div
                    key={`${c.id}-${idx}`}
                    className="flex flex-col justify-between gap-3 rounded-xl p-3 transition hover:bg-[#FCFBF6] sm:flex-row sm:items-center"
                  >
                    <div className="flex items-start gap-3">
                      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-[#FFFACD] text-[#B81104]">
                        <BookOpen className="h-5 w-5" aria-hidden="true" />
                      </span>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="rounded bg-[#B81104] px-1.5 py-0.5 text-[10px] font-bold text-[#FFFACD]">
                            {c.id}
                          </span>
                          <h3 className="text-sm font-bold text-[#302521]">
                            {lang === 'ar' ? c.nameAr : c.name}
                          </h3>
                        </div>
                        <p className="mt-0.5 text-xs text-[#6E645D]">
                          {c.teacher} · TA: {c.ta}
                        </p>
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={() => navigate('courses', { courseId: c.id, courseTab: 'Overview' })}
                      className="inline-flex min-h-[36px] items-center gap-1.5 rounded-lg bg-[#B81104] px-3.5 py-1.5 text-xs font-semibold text-white hover:bg-[#940E03]"
                    >
                      <span>{t('Open Course', 'فتح المقرر')}</span>
                    </button>
                  </div>
                );
              }

              const loc = entry.item;
              return (
                <div
                  key={`${loc.id}-${idx}`}
                  className="flex flex-col justify-between gap-3 rounded-xl p-3 transition hover:bg-[#FCFBF6] sm:flex-row sm:items-center"
                >
                  <div className="flex items-start gap-3">
                    <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-[#FFFACD] text-[#B81104]">
                      <Building2 className="h-5 w-5" aria-hidden="true" />
                    </span>
                    <div>
                      <h3 className="text-sm font-bold text-[#302521]">
                        {lang === 'ar' ? loc.nameAr : loc.name}
                      </h3>
                      <p className="mt-0.5 text-xs text-[#6E645D]">
                        {loc.category} · {loc.zone} · {loc.hours}
                      </p>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => navigate('map', { buildingId: loc.id })}
                    className="inline-flex min-h-[36px] items-center gap-1.5 rounded-lg bg-[#FFFACD] px-3 py-1.5 text-xs font-semibold text-[#B81104]"
                  >
                    <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>{t('View on Map', 'عرض على الخريطة')}</span>
                  </button>
                </div>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
