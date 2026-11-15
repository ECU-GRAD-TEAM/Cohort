import React, { useEffect, useMemo, useState } from 'react';
import {
  CalendarPlus,
  ClipboardCheck,
  FileCheck2,
  MapPin,
  MessageSquare,
  Paperclip,
  Search,
  Send,
  UserCheck,
  Users,
} from 'lucide-react';
import { useCohort } from '../../context/CohortContext';
import { DIRECTORY_PEOPLE } from '../../data/seedData';
import { StatusBadge } from '../common/StatusBadge';

export function MessagesPage() {
  const {
    role,
    lang,
    t,
    data,
    setData,
    profile,
    activeChatThread,
    setActiveChatThread,
    navigate,
    showToast,
  } = useCohort();

  const isStaff = role === 'Academic Staff';
  const [channelCategory, setChannelCategory] = useState('All');
  const [channelSearch, setChannelSearch] = useState('');
  const [draft, setDraft] = useState('');
  const [contextTag, setContextTag] = useState('');

  useEffect(() => {
    setChannelCategory('All');
    setContextTag('');
  }, [role]);

  const filterTabs = useMemo(
    () =>
      isStaff
        ? [
            { id: 'All', label: t('All', 'الكل') },
            { id: 'Advisees', label: t('Advisees', 'طلاب الإرشاد') },
            { id: 'Courses', label: t('Courses', 'المقررات') },
            { id: 'Academic Staff', label: t('Academic Staff & TAs', 'هيئة التدريس والمعيدون') },
            { id: 'Administration', label: t('Administration', 'الإدارة والتسجيل') },
          ]
        : [
            { id: 'All', label: t('All', 'الكل') },
            { id: 'Advisor', label: t('Academic Advisor', 'المرشد الأكاديمي') },
            { id: 'Courses', label: t('Courses', 'المقررات') },
            { id: 'Academic Staff', label: t('Academic Staff', 'هيئة التدريس') },
            { id: 'Individuals', label: t('Individuals', 'الأفراد والزملاء') },
            { id: 'Administration', label: t('Administration', 'الإدارة') },
          ],
    [isStaff, t]
  );

  const contextTagOptions = useMemo(
    () => [
      { value: '', label: t('No reference tag', 'بدون إشارة لملف') },
      { value: 'CS201 · Binary Search Tree Lab', label: t('CS201 · Binary Search Tree Lab', 'CS201 · معمل أشجار البحث') },
      { value: 'CS305 · BCNF Normalization', label: t('CS305 · BCNF Normalization', 'CS305 · تطبيع قواعد البيانات') },
      { value: '7-Course Registration Plan', label: t('7-Course Registration Plan', 'خطة تسجيل ٧ مقررات') },
      { value: 'Office Hours & Advising Request', label: t('Office Hours & Advising Request', 'طلب ساعة مكتبية / إرشاد') },
    ],
    [t]
  );

  const channels = useMemo(() => {
    if (isStaff) {
      const adviseeChannels = DIRECTORY_PEOPLE.filter((p) => p.category === 'Student').map((p) => {
        const studentCode = (p.subRole.split('·')[1] || p.subRole).trim();
        return {
          id: `direct-${p.id}`,
          group: 'Advisees',
          personName: lang === 'ar' ? p.nameAr : p.name,
          title: `${lang === 'ar' ? p.nameAr : p.name} · ${studentCode}`,
          subtitle: `GPA ${p.gpa} · ${t('Attendance', 'الحضور')} ${p.attendance}% · ${
            lang === 'ar' ? p.statusAr : p.status
          }`,
          badge:
            p.attendance < 85
              ? t('Attendance Watch', 'تنبيه حضور')
              : t('Advisee', 'طالب إرشاد'),
          buildingId: p.buildingId,
          studentMeta: p,
        };
      });

      const courseChannels = data.courses.map((c) => ({
        id: `course-${c.id}`,
        group: 'Courses',
        title: `${c.id} · ${lang === 'ar' ? c.nameAr : c.name}`,
        subtitle: t(
          `Course Channel · ${c.enrolled}/${c.capacity} enrolled`,
          `قناة المقرر · ${c.enrolled}/${c.capacity} مسجلين`
        ),
        badge: c.id === 'CS201' ? t('Coordinator', 'منسق المقرر') : t('Course', 'مقرر'),
        courseId: c.id,
      }));

      const staffColleagues = DIRECTORY_PEOPLE.filter(
        (p) => p.category === 'Academic Staff' && p.id !== 'p-michael'
      ).map((p) => ({
        id: `direct-${p.id}`,
        group: 'Academic Staff',
        personName: p.name,
        roleLabel: p.subRole,
        room: p.room,
        title: lang === 'ar' ? p.nameAr : p.name,
        subtitle: `${lang === 'ar' ? p.subRoleAr : p.subRole} · ${p.room}`,
        badge: p.subRole.includes('(TA)') ? t('TA', 'معيد') : t('Faculty', 'عضو تدريس'),
        buildingId: p.buildingId,
        officeHours: p.officeHours,
      }));

      const adminChannels = DIRECTORY_PEOPLE.filter((p) => p.category === 'Administrator').map((p) => ({
        id: `direct-${p.id}`,
        group: 'Administration',
        personName: p.name,
        roleLabel: p.subRole,
        room: p.room,
        title: lang === 'ar' ? p.nameAr : p.name,
        subtitle: `${lang === 'ar' ? p.subRoleAr : p.subRole} · ${p.room}`,
        badge: t('Admin', 'إدارة'),
        buildingId: p.buildingId,
        officeHours: p.officeHours,
      }));

      return [...adviseeChannels, ...courseChannels, ...staffColleagues, ...adminChannels];
    }

    const advisorChannel = {
      id: 'advisor-leila',
      group: 'Advisor',
      personName: 'Dr. Leila Hassan',
      roleLabel: 'Academic Advisor',
      title: t('Dr. Leila Hassan · Academic Advisor', 'د. ليلى حسن · المرشد الأكاديمي'),
      subtitle: t(
        'Academic Advising · Eng Bldg Room B-201 · Mon & Wed 11:00–13:00',
        'الإرشاد الأكاديمي · مبنى الهندسة B-201 · الإثنين والأربعاء ١١:٠٠–١٣:٠٠'
      ),
      badge: t('Advisor', 'المرشد'),
      room: 'Eng Bldg · Room B-201',
      officeHours: 'Mon & Wed 11:00–13:00',
      buildingId: 'Engineering',
    };

    const courseChannels = data.courses.map((c) => ({
      id: `course-${c.id}`,
      group: 'Courses',
      title: `${c.id} · ${lang === 'ar' ? c.nameAr : c.name}`,
      subtitle: t(`Course Group · ${c.teacher}`, `مجموعة المقرر · ${c.teacher}`),
      badge: t('Course', 'مقرر'),
      courseId: c.id,
    }));

    const academicStaffChannels = DIRECTORY_PEOPLE.filter(
      (p) => p.category === 'Academic Staff' && p.id !== 'p-leila'
    ).map((p) => ({
      id: `direct-${p.id}`,
      group: 'Academic Staff',
      personName: p.name,
      roleLabel: p.subRole,
      room: p.room,
      title: lang === 'ar' ? p.nameAr : p.name,
      subtitle: `${lang === 'ar' ? p.subRoleAr : p.subRole} · ${p.room}`,
      badge: p.subRole.includes('(TA)') ? t('TA', 'معيد') : t('Lecturer', 'محاضر'),
      buildingId: p.buildingId,
      officeHours: p.officeHours,
    }));

    const individualPeers = DIRECTORY_PEOPLE.filter(
      (p) => p.category === 'Student' && p.id !== 'p-alex'
    ).map((p) => ({
      id: `direct-${p.id}`,
      group: 'Individuals',
      personName: lang === 'ar' ? p.nameAr : p.name,
      title: lang === 'ar' ? p.nameAr : p.name,
      subtitle: `${lang === 'ar' ? p.subRoleAr : p.subRole} · ${lang === 'ar' ? p.departmentAr : p.department}`,
      badge: t('Peer', 'زميل'),
      buildingId: p.buildingId,
    }));

    const adminChannels = DIRECTORY_PEOPLE.filter((p) => p.category === 'Administrator').map((p) => ({
      id: `direct-${p.id}`,
      group: 'Administration',
      personName: p.name,
      roleLabel: p.subRole,
      room: p.room,
      title: lang === 'ar' ? p.nameAr : p.name,
      subtitle: `${lang === 'ar' ? p.subRoleAr : p.subRole} · ${p.room}`,
      badge: t('Admin', 'إدارة'),
      buildingId: p.buildingId,
      officeHours: p.officeHours,
    }));

    return [advisorChannel, ...courseChannels, ...academicStaffChannels, ...individualPeers, ...adminChannels];
  }, [data.courses, isStaff, lang, t]);

  const filteredChannels = useMemo(() => {
    const q = channelSearch.trim().toLowerCase();
    return channels.filter((ch) => {
      const catOk = channelCategory === 'All' || ch.group === channelCategory;
      const textOk =
        !q ||
        ch.title.toLowerCase().includes(q) ||
        ch.subtitle.toLowerCase().includes(q);
      return catOk && textOk;
    });
  }, [channels, channelCategory, channelSearch]);

  const currentChannel =
    channels.find((c) => c.id === activeChatThread) || filteredChannels[0] || channels[0];

  const messages = useMemo(() => {
    const existing = data.chatThreads[currentChannel?.id];
    if (existing && existing.length > 0) return existing;
    return [
      {
        id: `init-${currentChannel?.id}`,
        sender: currentChannel?.title || 'Cohort',
        senderId: currentChannel?.id || 'system',
        senderRole: currentChannel?.badge || 'Channel',
        text: t(
          `Direct conversation ready with ${currentChannel?.title}. Send a message or attach an academic reference below.`,
          `المحادثة جاهزة مع ${currentChannel?.title}. اكتب رسالتك أو أرفق إشارة أكاديمية بالأسفل.`
        ),
        time: 'Now',
      },
    ];
  }, [currentChannel, data.chatThreads, t]);

  const quickReplies = useMemo(
    () =>
      isStaff
        ? [
            t(
              'Your course registration plan has been reviewed and approved.',
              'تمت مراجعة واعتماد خطة تسجيل المقررات الخاصة بك.'
            ),
            t(
              'Please drop by office hours (Tue/Thu 14:00–16:00, Room B-214) to discuss your progress.',
              'يرجى الحضور خلال الساعات المكتبية لمناقشة تقدمك الدراسي.'
            ),
            t(
              'Reminder: Lab rubric and starter files are posted in Course Materials.',
              'تذكير: معايير التقييم وملفات المعمل متاحة في المواد الدراسية.'
            ),
          ]
        : [
            t(
              'Can we review my 7-course registration plan?',
              'هل يمكننا مراجعة خطة تسجيل الـ ٧ مقررات؟'
            ),
            t(
              'I have a question about the upcoming lab deadline.',
              'لدي استفسار بخصوص موعد تسليم المعمل القادم.'
            ),
            t(
              'Are office hours open this Tuesday?',
              'هل الساعات المكتبية متاحة يوم الثلاثاء؟'
            ),
          ],
    [isStaff, t]
  );

  const sendMessageText = (rawText, attachedTag = '') => {
    const clean = rawText.trim();
    if (!clean || !currentChannel) return;
    const nowTime = new Date().toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
    });

    const newMsg = {
      id: `msg-${Date.now()}`,
      sender: lang === 'ar' && profile.nameAr ? profile.nameAr : profile.name,
      senderId: profile.id,
      senderRole: role,
      text: clean,
      ...(attachedTag ? { contextTag: attachedTag } : {}),
      time: nowTime,
      mine: true,
    };

    setData((prev) => ({
      ...prev,
      chatThreads: {
        ...prev.chatThreads,
        [currentChannel.id]: [...(prev.chatThreads[currentChannel.id] || messages), newMsg],
      },
    }));
  };

  const handleBookFromChat = () => {
    if (!currentChannel?.officeHours) return;
    const slotText = `Next ${currentChannel.officeHours}`;
    const targetName = currentChannel.personName || currentChannel.title;
    const newApt = {
      id: `apt-${Date.now()}`,
      withName: targetName,
      roleLabel: currentChannel.roleLabel || currentChannel.badge,
      studentName: isStaff ? targetName : profile.name,
      slot: slotText,
      location: currentChannel.room || 'Eng Bldg',
      topic: t('Consultation requested via Cohort Chat', 'استشارة محجوزة عبر محادثات كوهورت'),
      status: 'Pending',
    };
    setData((prev) => ({
      ...prev,
      appointments: [newApt, ...prev.appointments],
    }));
    sendMessageText(
      t(
        `Requested office-hour appointment with ${targetName} (${currentChannel.officeHours} · ${currentChannel.room || 'Campus'}).`,
        `تم طلب موعد ساعات مكتبية مع ${targetName} (${currentChannel.officeHours}).`
      ),
      'Office Hours & Advising Request'
    );
    showToast(
      t(
        `Office-hour booking added for ${targetName}.`,
        `تمت إضافة طلب الموعد مع ${targetName}.`
      )
    );
  };

  const handleSend = (e) => {
    e.preventDefault();
    if (!draft.trim()) return;
    sendMessageText(draft, contextTag);
    setDraft('');
    setContextTag('');
  };

  return (
    <section className="page-enter space-y-5">
      <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-3">
        <div>
          <p className="text-[11px] font-bold tracking-widest uppercase text-[#B81104]">
            {isStaff
              ? t('FACULTY & ADVISOR COMMUNICATIONS', 'تواصل هيئة التدريس والإرشاد')
              : t('COHORT STUDENT COMMUNICATIONS', 'نظام المحادثات الطلابية')}
          </p>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-[#1A1715]">
            {isStaff
              ? t('Advisees, Courses, Academic Staff & Admin Chats', 'طلاب الإرشاد والمقررات والزملاء والإدارة')
              : t('Academic Advisor, Courses, Staff & Peer Chats', 'المرشد الأكاديمي والمقررات وهيئة التدريس والأفراد')}
          </h1>
          <p className="text-xs sm:text-sm text-[#6E645D] mt-1">
            {isStaff
              ? t(
                  `Signed in as ${lang === 'ar' ? profile.nameAr : profile.name} (${profile.id}) · Respond to advisees, TAs, colleagues, and course channels.`,
                  `مسجل بصفتك ${profile.nameAr} (${profile.id}) · متابعة طلاب الإرشاد والمعيدين والزملاء وقنوات المقررات.`
                )
              : t(
                  `Signed in as ${lang === 'ar' ? profile.nameAr : profile.name} (${profile.id}) · Default channel connects directly to your Academic Advisor.`,
                  `مسجل بصفتك ${profile.nameAr} (${profile.id}) · القناة الافتراضية متصلة بمرشدك الأكاديمي.`
                )}
          </p>
        </div>

        <span className="self-start inline-flex items-center gap-1.5 rounded-xl border border-[#E8E3D9] bg-white px-3.5 py-2 text-xs font-bold text-[#302521]">
          <UserCheck className="h-4 w-4 text-[#B81104]" aria-hidden="true" />
          <span>{isStaff ? t('Advisor & Faculty Inbox', 'صندوق المرشد والتدريس') : t('Student Inbox', 'صندوق الطالب')}</span>
        </span>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* Channel Sidebar */}
        <aside className="lg:col-span-4 cohort-card rounded-2xl p-4 space-y-3">
          <div className="relative">
            <Search className="w-4 h-4 text-[#6E645D] absolute start-3 top-1/2 -translate-y-1/2" aria-hidden="true" />
            <input
              type="text"
              value={channelSearch}
              onChange={(e) => setChannelSearch(e.target.value)}
              aria-label={t('Search chats', 'البحث في المحادثات')}
              placeholder={
                isStaff
                  ? t('Filter advisees, courses, staff, admins...', 'بحث عن طالب أو مقرر أو زميل أو إدارة...')
                  : t('Filter advisor, courses, staff, peers...', 'بحث عن مرشد أو مقرر أو دكتور أو زميل...')
              }
              className="w-full rounded-xl border border-[#E5DCCF] bg-[#FDFBF7] ps-9 pe-3 py-2 text-xs text-[#1A1715]"
            />
          </div>

          <div className="flex flex-wrap gap-1.5">
            {filterTabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setChannelCategory(tab.id)}
                className={`px-2.5 py-1 rounded-full text-[11px] font-bold border transition-colors ${
                  channelCategory === tab.id
                    ? 'bg-[#B81104] text-[#FFFACD] border-[#B81104]'
                    : 'bg-white text-[#6E645D] border-[#E5DCCF] hover:border-[#B81104]/40'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="space-y-1.5 max-h-[440px] overflow-y-auto pe-1">
            {filteredChannels.length === 0 ? (
              <p className="py-6 text-center text-xs text-[#6E645D]">
                {t('No matching channels found.', 'لا توجد محادثات مطابقة.')}
              </p>
            ) : (
              filteredChannels.map((ch) => {
                const active = ch.id === currentChannel?.id;
                const threadMsgs = data.chatThreads[ch.id] || [];
                const lastPreview = threadMsgs[threadMsgs.length - 1]?.text;
                return (
                  <button
                    key={ch.id}
                    type="button"
                    onClick={() => setActiveChatThread(ch.id)}
                    className={`w-full text-start rounded-xl p-3 border transition-colors ${
                      active
                        ? 'bg-[#FFFACD] border-[#B81104]'
                        : 'bg-[#FDFBF7] border-transparent hover:border-[#E5DCCF]'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs font-extrabold text-[#1A1715] truncate">
                        {ch.title}
                      </span>
                      <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-[#B81104]/10 text-[#960D03] shrink-0">
                        {ch.badge}
                      </span>
                    </div>
                    <p className="text-[11px] text-[#6E645D] truncate mt-0.5">{ch.subtitle}</p>
                    {lastPreview ? (
                      <p className="text-[11px] text-[#302521]/80 truncate mt-1">{lastPreview}</p>
                    ) : null}
                  </button>
                );
              })
            )}
          </div>
        </aside>

        {/* Active Chat Thread */}
        <div className="lg:col-span-8 cohort-card rounded-2xl p-4 sm:p-5 flex flex-col justify-between min-h-[500px]">
          <div className="space-y-3 border-b border-[#EFE7DA] pb-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-[#B81104] text-[#FFFACD] flex items-center justify-center font-bold shrink-0">
                  {currentChannel?.group === 'Courses' ? (
                    <Users className="w-5 h-5" aria-hidden="true" />
                  ) : (
                    <MessageSquare className="w-5 h-5" aria-hidden="true" />
                  )}
                </div>
                <div>
                  <h2 className="text-sm sm:text-base font-extrabold text-[#1A1715]">
                    {currentChannel?.title}
                  </h2>
                  <p className="text-xs text-[#6E645D]">{currentChannel?.subtitle}</p>
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                {currentChannel?.officeHours ? (
                  <button
                    type="button"
                    onClick={handleBookFromChat}
                    className="inline-flex items-center gap-1 rounded-lg border border-[#E9DBA9] bg-[#FFFACD] px-2.5 py-1 text-[11px] font-bold text-[#960D03] hover:bg-[#FFF2B5]"
                  >
                    <CalendarPlus className="w-3.5 h-3.5" aria-hidden="true" />
                    <span>{t('Book Office Hour', 'حجز ساعة مكتبية')}</span>
                  </button>
                ) : null}
                {currentChannel?.buildingId ? (
                  <button
                    type="button"
                    onClick={() => navigate('map', { buildingId: currentChannel.buildingId })}
                    className="inline-flex items-center gap-1 rounded-lg border border-[#E5DCCF] bg-white px-2.5 py-1 text-[11px] font-bold text-[#302521] hover:border-[#B81104]"
                  >
                    <MapPin className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
                    <span>{t('Map', 'الخريطة')}</span>
                  </button>
                ) : null}
                {currentChannel?.courseId ? (
                  <button
                    type="button"
                    onClick={() =>
                      navigate('courses', { courseId: currentChannel.courseId, courseTab: 'Overview' })
                    }
                    className="inline-flex items-center gap-1 rounded-lg border border-[#E5DCCF] bg-white px-2.5 py-1 text-[11px] font-bold text-[#302521] hover:border-[#B81104]"
                  >
                    <span>{t('Open Course', 'فتح المقرر')}</span>
                  </button>
                ) : null}
                <span className="px-2.5 py-1 rounded-full bg-[#FFFACD] text-[#960D03] text-xs font-bold">
                  {currentChannel?.badge}
                </span>
              </div>
            </div>

            {/* Advisor Context Bar when Staff views an Advisee */}
            {isStaff && currentChannel?.group === 'Advisees' && currentChannel.studentMeta ? (
              <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[#E9DBA9] bg-[#FFFACD]/60 px-3.5 py-2.5">
                <div className="flex flex-wrap items-center gap-2.5 text-xs">
                  <span className="font-extrabold text-[#1A1715] tabular-nums">
                    GPA {currentChannel.studentMeta.gpa}
                  </span>
                  <span className="text-[#6E645D]">·</span>
                  <span className="font-bold text-[#1A1715] tabular-nums">
                    {t('Attendance:', 'الحضور:')} {currentChannel.studentMeta.attendance}%
                  </span>
                  <StatusBadge
                    status={currentChannel.studentMeta.status}
                    label={
                      lang === 'ar'
                        ? currentChannel.studentMeta.statusAr
                        : currentChannel.studentMeta.status
                    }
                  />
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={() => navigate('academic-affairs')}
                    className="inline-flex items-center gap-1 rounded-lg bg-white border border-[#E5DCCF] px-2.5 py-1 text-[11px] font-bold text-[#302521] hover:border-[#B81104]"
                  >
                    <FileCheck2 className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
                    <span>{t('Review Petitions', 'مراجعة الالتماسات')}</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => navigate('registration')}
                    className="inline-flex items-center gap-1 rounded-lg bg-[#B81104] px-2.5 py-1 text-[11px] font-bold text-[#FFFACD] hover:bg-[#960D03]"
                  >
                    <ClipboardCheck className="w-3.5 h-3.5" aria-hidden="true" />
                    <span>{t('Approve Registration', 'اعتماد التسجيل')}</span>
                  </button>
                </div>
              </div>
            ) : null}
          </div>

          <div className="flex-1 py-4 space-y-3 overflow-y-auto max-h-[320px] pe-1">
            {messages.map((m) => {
              const isMine = m.senderId ? m.senderId === profile.id : m.senderRole === role;
              return (
                <div
                  key={m.id}
                  className={`flex ${isMine ? 'justify-end' : 'justify-start'}`}
                >
                  <div
                    className={`max-w-md rounded-2xl px-4 py-2.5 text-sm space-y-1.5 ${
                      isMine
                        ? 'bg-[#B81104] text-[#FFFACD]'
                        : 'bg-[#FDFBF7] border border-[#E5DCCF] text-[#1A1715]'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-4 text-[11px] opacity-85 font-bold">
                      <span>
                        {m.sender} · {m.senderRole}
                      </span>
                      <span className="tabular-nums">{m.time}</span>
                    </div>
                    {m.contextTag ? (
                      <div
                        className={`inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-[10px] font-bold ${
                          isMine
                            ? 'bg-white/15 text-[#FFFACD]'
                            : 'bg-[#FFFACD] border border-[#E9DBA9] text-[#960D03]'
                        }`}
                      >
                        <Paperclip className="w-3 h-3" aria-hidden="true" />
                        <span>{m.contextTag}</span>
                      </div>
                    ) : null}
                    <p className="leading-relaxed">{m.text}</p>
                  </div>
                </div>
              );
            })}
          </div>

          <div className="pt-3 border-t border-[#EFE7DA] space-y-2.5">
            {/* Role-specific quick replies */}
            <div className="flex flex-wrap gap-1.5">
              {quickReplies.map((reply) => (
                <button
                  key={reply}
                  type="button"
                  onClick={() => setDraft(reply)}
                  className="rounded-full border border-[#E9DBA9] bg-[#FFFACD]/60 px-3 py-1 text-[11px] font-semibold text-[#302521] hover:bg-[#FFFACD] text-start transition"
                >
                  {reply}
                </button>
              ))}
            </div>

            <form onSubmit={handleSend} className="flex flex-wrap sm:flex-nowrap gap-2">
              <div className="flex items-center gap-1.5 rounded-2xl border border-[#E5DCCF] bg-[#FCFBF6] px-2.5 py-2 shrink-0">
                <Paperclip className="w-3.5 h-3.5 text-[#B81104]" aria-hidden="true" />
                <select
                  aria-label={t('Attach academic context tag', 'إرفاق إشارة أكاديمية')}
                  value={contextTag}
                  onChange={(e) => setContextTag(e.target.value)}
                  className="bg-transparent text-xs font-semibold text-[#302521] focus:outline-none max-w-[175px]"
                >
                  {contextTagOptions.map((opt) => (
                    <option key={opt.label} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </div>
              <input
                type="text"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                aria-label={t('Write a message', 'اكتب رسالة')}
                placeholder={
                  isStaff
                    ? t('Reply as Dr. Michael Tan...', 'اكتب ردك بصفتك المرشد أو المحاضر...')
                    : t('Write a message as Alex Chen...', 'اكتب رسالتك هنا...')
                }
                className="flex-1 min-w-[180px] rounded-2xl border border-[#E5DCCF] bg-white px-4 py-2.5 text-sm text-[#1A1715]"
              />
              <button
                type="submit"
                className="inline-flex items-center gap-2 px-5 py-2.5 rounded-2xl bg-[#B81104] text-[#FFFACD] text-sm font-bold hover:bg-[#960D03]"
              >
                <Send className="w-4 h-4" aria-hidden="true" />
                <span>{t('Send', 'إرسال')}</span>
              </button>
            </form>
          </div>
        </div>
      </div>
    </section>
  );
}
