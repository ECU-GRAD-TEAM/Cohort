import React, { useMemo, useState } from 'react';
import {
  Building2,
  Calendar,
  Clock,
  Compass,
  MapPin,
  MessageSquare,
  Search,
  Users,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { CAMPUS_LOCATIONS, DIRECTORY_PEOPLE } from '../../data/seedData';
import { StatusBadge } from '../common/StatusBadge';

const ZONE_LAYOUT = [
  { id: 'Library', gridPos: 'col-start-1 row-start-1', wingEn: 'North Wing', wingAr: 'الجناح الشمالي' },
  { id: 'TA Wing', gridPos: 'col-start-2 row-start-1', wingEn: 'North Annex', wingAr: 'الملحق الشمالي' },
  { id: 'Engineering', gridPos: 'col-start-1 row-start-2', wingEn: 'Central Campus', wingAr: 'الحرم الأوسط' },
  { id: 'Science', gridPos: 'col-start-2 row-start-2', wingEn: 'East Wing', wingAr: 'الجناح الشرقي' },
  { id: 'Admin Bldg', gridPos: 'col-span-2 row-start-3', wingEn: 'Main Plaza', wingAr: 'الساحة الرئيسية' },
];

export function MapPage() {
  const { role, lang, t, data, selectedBuildingId, setSelectedBuildingId, navigate } = useCohort();
  const [catFilter, setCatFilter] = useState('All');
  const [query, setQuery] = useState('');

  const categories = useMemo(
    () => [
      { id: 'All', en: 'All', ar: 'الكل' },
      { id: 'Labs & Halls', en: 'Labs & Halls', ar: 'المعامل والقاعات' },
      { id: 'TAs Rooms', en: 'TAs Rooms', ar: 'غرف المعيدين' },
      { id: 'Administrators', en: 'Administrators', ar: 'الإدارة والتسجيل' },
      { id: 'Facilities', en: 'Facilities', ar: 'المرافق والمكتبة' },
    ],
    []
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return CAMPUS_LOCATIONS.filter((loc) => {
      const catOk = catFilter === 'All' || loc.category === catFilter;
      if (!catOk) return false;
      if (!q) return true;
      const peopleHere = DIRECTORY_PEOPLE.filter(
        (p) => p.buildingId === loc.id && p.category !== 'Student'
      );
      return (
        loc.name.toLowerCase().includes(q) ||
        loc.nameAr.toLowerCase().includes(q) ||
        loc.zone.toLowerCase().includes(q) ||
        loc.rooms.some((rm) => rm.toLowerCase().includes(q)) ||
        peopleHere.some(
          (p) =>
            p.name.toLowerCase().includes(q) ||
            p.nameAr.toLowerCase().includes(q) ||
            p.subRole.toLowerCase().includes(q)
        )
      );
    });
  }, [catFilter, query]);

  const active =
    filtered.find((l) => l.id === selectedBuildingId) ||
    CAMPUS_LOCATIONS.find((l) => l.id === selectedBuildingId) ||
    filtered[0] ||
    CAMPUS_LOCATIONS[0];

  const peopleInBuilding = useMemo(
    () =>
      DIRECTORY_PEOPLE.filter(
        (p) => p.buildingId === active.id && p.category !== 'Student'
      ),
    [active.id]
  );

  const classesInBuilding = useMemo(
    () => data.schedule.filter((s) => s.buildingId === active.id),
    [active.id, data.schedule]
  );

  return (
    <section className="page-enter space-y-6">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-end">
        <div>
          <p className="text-[11px] font-bold tracking-widest text-[#6E645D] uppercase">
            {t('CAMPUS MAP & DIRECTORY', 'خريطة الجامعة ودليل القاعات')}
          </p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-[#302521] sm:text-3xl">
            {t('Labs, Halls, TAs’ Rooms & Administrators', 'المعامل والقاعات وغرف المعيدين والإدارة')}
          </h1>
        </div>

        <div className="relative w-full sm:w-80">
          <Search className="h-4 w-4 text-[#6E645D] absolute start-3 top-1/2 -translate-y-1/2" aria-hidden="true" />
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label={t('Search buildings, rooms, or staff', 'ابحث عن مبنى أو قاعة أو عضو هيئة تدريس')}
            placeholder={t('Search room (Lab C-102), hall, or staff...', 'ابحث عن قاعة أو معمل أو دكتور...')}
            className="w-full min-h-[42px] rounded-xl border border-[#E8E3D9] bg-white ps-9 pe-3 text-xs text-[#302521]"
          />
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {categories.map((cat) => (
          <button
            key={cat.id}
            type="button"
            onClick={() => setCatFilter(cat.id)}
            className={`rounded-xl border px-3.5 py-2 text-xs font-bold transition ${
              catFilter === cat.id
                ? 'border-[#B81104] bg-[#B81104] text-[#FFFACD]'
                : 'border-[#E8E3D9] bg-white text-[#302521] hover:bg-[#FFF9E4]'
            }`}
          >
            {lang === 'ar' ? cat.ar : cat.en}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
        {/* Left: Visual Campus Zone Blueprint + Building Cards */}
        <div className="space-y-5 lg:col-span-7">
          <div className="cohort-card p-5 space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <Compass className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                <h2 className="text-sm font-extrabold text-[#302521]">
                  {t('Interactive Campus Zone Blueprint', 'مخطط مناطق الحرم الجامعي التفاعلي')}
                </h2>
              </div>
              <span className="text-[11px] font-semibold text-[#6E645D]">
                {t('Select a building pin to inspect', 'اختر مبنى لعرض التفاصيل')}
              </span>
            </div>

            <div className="grid grid-cols-2 grid-rows-3 gap-2.5 rounded-2xl border border-[#E8E3D9] bg-[#FCFBF6] p-3.5">
              {ZONE_LAYOUT.map((zone) => {
                const bldg = CAMPUS_LOCATIONS.find((l) => l.id === zone.id);
                if (!bldg) return null;
                const isSelected = active.id === bldg.id;
                const inFiltered = filtered.some((f) => f.id === bldg.id);
                return (
                  <button
                    key={bldg.id}
                    type="button"
                    onClick={() => setSelectedBuildingId(bldg.id)}
                    className={`${zone.gridPos} rounded-xl border p-3 text-start transition ${
                      isSelected
                        ? 'border-[#B81104] bg-[#FFFACD] shadow-sm'
                        : inFiltered
                          ? 'border-[#E8E3D9] bg-white hover:border-[#B81104]/50'
                          : 'border-[#E8E3D9] bg-white/50 opacity-50 hover:opacity-90'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-1.5">
                      <span className="text-[10px] font-bold uppercase tracking-wider text-[#B81104]">
                        {lang === 'ar' ? zone.wingAr : zone.wingEn}
                      </span>
                      <MapPin
                        className={`h-3.5 w-3.5 shrink-0 ${
                          isSelected ? 'text-[#B81104]' : 'text-[#6E645D]'
                        }`}
                        aria-hidden="true"
                      />
                    </div>
                    <p className="mt-1 text-xs font-extrabold text-[#302521] truncate">
                      {lang === 'ar' ? bldg.nameAr : bldg.name}
                    </p>
                  </button>
                );
              })}
            </div>
          </div>

          {filtered.length === 0 ? (
            <div className="cohort-card p-8 text-center text-sm text-[#6E645D]">
              {t('No buildings, rooms, or staff matched your search.', 'لم يتم العثور على مبنى أو قاعة مطابقة.')}
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              {filtered.map((loc) => {
                const selected = active.id === loc.id;
                return (
                  <button
                    key={loc.id}
                    type="button"
                    onClick={() => setSelectedBuildingId(loc.id)}
                    className={`rounded-2xl border p-5 text-start transition ${
                      selected
                        ? 'border-[#B81104] bg-[#FFFACD] shadow-sm'
                        : 'border-[#E8E3D9] bg-white hover:border-[#B81104]/50'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="rounded-md bg-white/80 px-2 py-0.5 text-[10px] font-bold text-[#B81104]">
                        {lang === 'ar' && loc.categoryAr ? loc.categoryAr : loc.category}
                      </span>
                      <MapPin className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
                    </div>
                    <h2 className="mt-3 text-base font-bold text-[#302521]">
                      {lang === 'ar' ? loc.nameAr : loc.name}
                    </h2>
                    <p className="mt-1 text-xs text-[#6E645D]">
                      {lang === 'ar' && loc.zoneAr ? loc.zoneAr : loc.zone} · {loc.rooms.length} {t('rooms', 'قاعات')}
                    </p>
                  </button>
                );
              })}
            </div>
          )}
        </div>

        {/* Right: Building Inspector */}
        <div className="cohort-card p-6 lg:col-span-5 space-y-5 h-fit">
          <div>
            <div className="flex items-center gap-2 text-[#B81104]">
              <Building2 className="h-5 w-5" aria-hidden="true" />
              <span className="text-xs font-bold uppercase tracking-wider">
                {lang === 'ar' && active.categoryAr ? active.categoryAr : active.category}
              </span>
            </div>
            <h2 className="mt-1 text-xl font-bold text-[#302521]">
              {lang === 'ar' ? active.nameAr : active.name}
            </h2>
            <p className="mt-1 flex items-center gap-1.5 text-xs text-[#6E645D]">
              <Clock className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
              <span>
                {lang === 'ar' && active.zoneAr ? active.zoneAr : active.zone} · {active.hours}
              </span>
            </p>
            <p className="mt-1.5 text-xs text-[#16845B] font-semibold">
              {lang === 'ar' && active.accessibilityAr ? active.accessibilityAr : active.accessibility}
            </p>
          </div>

          <div className="border-t border-[#E8E3D9] pt-4">
            <h3 className="text-xs font-bold uppercase tracking-wider text-[#6E645D] mb-2">
              {t('Rooms & Labs Inside', 'القاعات والمعامل')}
            </h3>
            <ul className="space-y-1.5">
              {(lang === 'ar' && active.roomsAr ? active.roomsAr : active.rooms).map((rm) => (
                <li
                  key={rm}
                  className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] px-3 py-2 text-xs font-semibold text-[#302521]"
                >
                  {rm}
                </li>
              ))}
            </ul>
          </div>

          <div className="border-t border-[#E8E3D9] pt-4 space-y-2.5">
            <div className="flex items-center gap-1.5">
              <Users className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
              <h3 className="text-xs font-bold uppercase tracking-wider text-[#6E645D]">
                {t('Staff, TAs & Administrators Here', 'هيئة التدريس والمعيدون والإدارة')}
              </h3>
            </div>
            {peopleInBuilding.length === 0 ? (
              <p className="text-xs text-[#6E645D]">
                {t('Shared campus study & quiet rooms facility.', 'مبنى مخصص للدراسة والقاعات المشتركة.')}
              </p>
            ) : (
              peopleInBuilding.map((p) => (
                <div
                  key={p.id}
                  className="rounded-xl border border-[#E8E3D9] bg-[#FCFBF6] p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2.5"
                >
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="text-xs font-extrabold text-[#302521]">
                        {lang === 'ar' ? p.nameAr : p.name}
                      </span>
                      <StatusBadge status={p.status} label={lang === 'ar' ? p.statusAr : p.status} />
                    </div>
                    <p className="text-[11px] text-[#6E645D] truncate">
                      {lang === 'ar' ? p.subRoleAr : p.subRole}
                    </p>
                    <p className="text-[11px] font-semibold text-[#302521] mt-0.5">
                      {p.room} · {p.officeHours}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() =>
                      navigate('messages', {
                        chatThread:
                          p.isAdvisor && role === 'Student' ? 'advisor-leila' : `direct-${p.id}`,
                      })
                    }
                    className="self-start sm:self-center shrink-0 inline-flex items-center gap-1 rounded-lg bg-[#B81104] px-3 py-1.5 text-[11px] font-bold text-[#FFFACD] hover:bg-[#940E03]"
                  >
                    <MessageSquare className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>{t('Chat', 'محادثة')}</span>
                  </button>
                </div>
              ))
            )}
          </div>

          <div className="border-t border-[#E8E3D9] pt-4 space-y-2">
            <div className="flex items-center gap-1.5">
              <Calendar className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
              <h3 className="text-xs font-bold uppercase tracking-wider text-[#6E645D]">
                {t('Classes Scheduled Here', 'الجلسات المجدولة بهذا المبنى')}
              </h3>
            </div>
            {classesInBuilding.length === 0 ? (
              <p className="text-xs text-[#6E645D]">
                {t('No scheduled timetable sessions in this building.', 'لا توجد جلسات مجدولة في هذا المبنى.')}
              </p>
            ) : (
              classesInBuilding.map((s) => (
                <div
                  key={s.id}
                  className="flex items-center justify-between gap-2 rounded-xl border border-[#E8E3D9] bg-white px-3 py-2 text-xs"
                >
                  <div>
                    <span className="font-bold text-[#302521]">
                      {s.courseCode} · {s.type}
                    </span>
                    <p className="text-[11px] text-[#6E645D] tabular-nums">
                      {s.day} {s.start}–{s.end} · {s.location}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() =>
                      navigate('courses', { courseId: s.courseCode, courseTab: 'Overview' })
                    }
                    className="font-bold text-[#B81104] hover:underline text-[11px]"
                  >
                    {t('Course →', 'المقرر ←')}
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </section>
  );
}
