import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { INITIAL_SEED } from '../data/seedData';
import { useAccount } from '../auth/AuthGate';
import { toProfile, toScheduleItems, toStaffCourses, toStudentCourses, workspaceRole } from '../lib/liveData';

const STORAGE_KEY = 'cohort-lms-v6';

const CohortContext = createContext(null);

function loadInitialData() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return structuredClone(INITIAL_SEED);
    const parsed = JSON.parse(raw);
    const validRole = parsed.role === 'Academic Staff' ? 'Academic Staff' : 'Student';
    return {
      ...structuredClone(INITIAL_SEED),
      ...parsed,
      role: validRole,
      profiles: {
        ...INITIAL_SEED.profiles,
        ...(parsed.profiles || {}),
      },
      prefs: {
        Student: { ...INITIAL_SEED.prefs.Student, ...(parsed.prefs?.Student || {}) },
        'Academic Staff': {
          ...INITIAL_SEED.prefs['Academic Staff'],
          ...(parsed.prefs?.['Academic Staff'] || {}),
        },
      },
      chatThreads: {
        ...structuredClone(INITIAL_SEED.chatThreads),
        ...(parsed.chatThreads || {}),
      },
      studentCalendarEvents: Array.isArray(parsed.studentCalendarEvents)
        ? parsed.studentCalendarEvents
        : structuredClone(INITIAL_SEED.studentCalendarEvents),
    };
  } catch {
    return structuredClone(INITIAL_SEED);
  }
}

// Fields a local profile edit may not change: they come from the signed-in account.
const ACCOUNT_FIELDS = ['name', 'nameAr', 'email', 'university'];

/**
 * The signed-in person's courses and timetable, loaded fresh from the API on every visit and never
 * saved in the browser. Students get their enrolments, grades and assigned meetings; academic staff
 * the sections they teach and their meetings.
 */
function useLiveData(api, me, role) {
  const [live, setLive] = useState({ status: 'loading', courses: [], schedule: [], error: null });
  const load = useCallback(async () => {
    setLive((prev) => ({ ...prev, status: 'loading', error: null }));
    try {
      if (role === 'Academic Staff') {
        const [teaching, schedule] = await Promise.all([api.teaching(), api.schedule()]);
        setLive({
          status: 'ready',
          courses: toStaffCourses(teaching.sections, me.displayName),
          schedule: toScheduleItems(schedule.meetings),
          error: null,
        });
      } else {
        const [enrollments, grades, schedule] = await Promise.all([api.enrollments(), api.grades(), api.schedule()]);
        setLive({
          status: 'ready',
          courses: toStudentCourses(enrollments.enrollments, grades.grades, schedule.meetings),
          schedule: toScheduleItems(schedule.meetings),
          grades: grades.grades,
          error: null,
        });
      }
    } catch (error) {
      setLive((prev) => ({ ...prev, status: 'error', error }));
    }
  }, [api, me.displayName, role]);
  useEffect(() => {
    load();
  }, [load]);
  return { ...live, reload: load };
}

export function CohortProvider({ children }) {
  const { me, api, signOut } = useAccount();
  const role = workspaceRole(me);
  const [data, setData] = useState(loadInitialData);
  const live = useLiveData(api, me, role);
  const [page, setPage] = useState('dashboard');
  const [selectedCourseId, setSelectedCourseId] = useState('');
  const [courseTab, setCourseTab] = useState('Overview');
  const [selectedBuildingId, setSelectedBuildingId] = useState('Engineering');
  const [activeChatThread, setActiveChatThread] = useState(() =>
    role === 'Academic Staff' ? 'direct-p-alex' : 'advisor-leila'
  );
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [toastMessage, setToastMessage] = useState('');
  const toastTimerRef = useRef(null);

  const lang = data.language === 'ar' ? 'ar' : 'en';
  const profile = useMemo(() => {
    // Edits made on this device, kept per account so people sharing a browser don't see each other's.
    const edits = { ...(data.profileEdits?.[me.id] ?? {}) };
    ACCOUNT_FIELDS.forEach((field) => delete edits[field]);
    return { ...toProfile(me, role), ...edits };
  }, [data.profileEdits, me, role]);
  const prefs = data.prefs[role];

  // The pages read courses, the timetable and the profile from `data`; those come from the API.
  const liveData = useMemo(
    () => ({
      ...data,
      role,
      courses: live.courses,
      // Live meetings, plus any session added on this device from the timetable page.
      schedule: [...live.schedule, ...data.schedule.filter((s) => s.local)],
      publishedGrades: live.grades ?? [],
      profiles: { ...data.profiles, [role]: profile },
    }),
    [data, live.courses, live.grades, live.schedule, profile, role]
  );

  // Keep the selected course pointing at one the person actually has.
  useEffect(() => {
    if (live.courses.length > 0 && !live.courses.some((c) => c.id === selectedCourseId)) {
      setSelectedCourseId(live.courses[0].id);
    }
  }, [live.courses, selectedCourseId]);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    } catch {
      // Ignore storage quota warnings in demo
    }
  }, [data]);

  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }, [lang]);

  useEffect(() => {
    document.body.classList.toggle('reduce-motion', Boolean(prefs?.reduceMotion));
  }, [prefs?.reduceMotion]);

  const showToast = useCallback((msg) => {
    setToastMessage(msg);
    if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    toastTimerRef.current = setTimeout(() => setToastMessage(''), 3200);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimerRef.current) clearTimeout(toastTimerRef.current);
    };
  }, []);

  // Global keyboard shortcut: / or Ctrl+K / Cmd+K opens Global Search
  useEffect(() => {
    const onKeyDown = (e) => {
      const tag = document.activeElement?.tagName;
      const inInput = ['INPUT', 'TEXTAREA', 'SELECT'].includes(tag);
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setSearchOpen(true);
      } else if (e.key === '/' && !inInput) {
        e.preventDefault();
        setSearchOpen(true);
      } else if (e.key === 'Escape') {
        setSearchOpen(false);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  const t = useCallback((en, ar) => (lang === 'ar' && ar ? ar : en), [lang]);

  const navigate = useCallback(
    (nextPage, options = {}) => {
      setPage(nextPage);
      if (options.courseId) setSelectedCourseId(options.courseId);
      if (options.courseTab) setCourseTab(options.courseTab);
      if (options.buildingId) setSelectedBuildingId(options.buildingId);
      if (options.chatThread) setActiveChatThread(options.chatThread);
      setSearchOpen(false);
      window.scrollTo({ top: 0, behavior: prefs?.reduceMotion ? 'auto' : 'smooth' });
    },
    [prefs?.reduceMotion]
  );

  const toggleLanguage = useCallback(() => {
    setData((prev) => ({
      ...prev,
      language: prev.language === 'ar' ? 'en' : 'ar',
    }));
  }, []);

  const updateProfile = useCallback(
    (updates) => {
      setData((prev) => ({
        ...prev,
        profileEdits: {
          ...(prev.profileEdits ?? {}),
          [me.id]: { ...(prev.profileEdits?.[me.id] ?? {}), ...updates },
        },
      }));
      showToast(t('Profile details saved on this device.', 'تم حفظ بيانات الملف الشخصي على هذا الجهاز.'));
    },
    [me.id, showToast, t]
  );

  const updatePrefs = useCallback(
    (updates) => {
      setData((prev) => ({
        ...prev,
        prefs: {
          ...prev.prefs,
          [role]: {
            ...prev.prefs[role],
            ...updates,
          },
        },
      }));
      showToast(t('Notification & display preferences saved.', 'تم حفظ تفضيلات الإشعارات والعرض.'));
    },
    [role, showToast, t]
  );

  const addPetition = useCallback(
    (petition) => {
      setData((prev) => ({
        ...prev,
        petitions: [
          {
            id: `pet-${Date.now()}`,
            student: profile.name,
            studentId: profile.id,
            date: new Date().toISOString().slice(0, 10),
            status: 'Pending Advisor',
            ...petition,
          },
          ...prev.petitions,
        ],
      }));
      showToast(t('Academic petition submitted to advisor queue.', 'تم إرسال الالتماس الأكاديمي للمرشد.'));
    },
    [profile, showToast, t]
  );

  const updatePetitionStatus = useCallback(
    (id, status) => {
      setData((prev) => ({
        ...prev,
        petitions: prev.petitions.map((p) => (p.id === id ? { ...p, status } : p)),
      }));
      showToast(t(`Petition marked as ${status}.`, `تم تحديث حالة الالتماس إلى ${status}.`));
    },
    [showToast, t]
  );

  const roleNotifications = useMemo(
    () =>
      data.notifications.filter(
        (n) => !n.forRole || n.forRole === 'All' || n.forRole === role
      ),
    [data.notifications, role]
  );

  const unreadCount = useMemo(
    () =>
      roleNotifications.filter(
        (n) => !n.read && (!n.prefKey || prefs?.[n.prefKey] !== false)
      ).length,
    [prefs, roleNotifications]
  );

  const markAllNotificationsRead = useCallback(() => {
    setData((prev) => ({
      ...prev,
      notifications: prev.notifications.map((n) =>
        !n.forRole || n.forRole === 'All' || n.forRole === role ? { ...n, read: true } : n
      ),
    }));
    showToast(t('All notifications marked as read.', 'تم تحديد جميع الإشعارات كمقروءة.'));
  }, [role, showToast, t]);

  const markNotificationRead = useCallback((id) => {
    setData((prev) => ({
      ...prev,
      notifications: prev.notifications.map((n) => (n.id === id ? { ...n, read: true } : n)),
    }));
  }, []);

  const exportWorkspaceData = useCallback(() => {
    // Only this account's data: edits other people made on this device stay out of the file.
    const { profileEdits: _otherAccounts, ...workspace } = liveData;
    const blob = new Blob([JSON.stringify(workspace, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `cohort-lms-${role.toLowerCase().replace(/\s+/g, '-')}-export.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    showToast(t('Workspace data exported as JSON.', 'تم تصدير بيانات مساحة العمل بصيغة JSON.'));
  }, [liveData, role, showToast, t]);

  const value = useMemo(
    () => ({
      data: liveData,
      setData,
      role,
      account: me,
      api,
      signOut,
      live,
      lang,
      toggleLanguage,
      t,
      profile,
      prefs,
      updateProfile,
      updatePrefs,
      page,
      navigate,
      selectedCourseId,
      setSelectedCourseId,
      courseTab,
      setCourseTab,
      selectedBuildingId,
      setSelectedBuildingId,
      activeChatThread,
      setActiveChatThread,
      searchOpen,
      setSearchOpen,
      searchQuery,
      setSearchQuery,
      toastMessage,
      showToast,
      addPetition,
      updatePetitionStatus,
      unreadCount,
      markAllNotificationsRead,
      markNotificationRead,
      exportWorkspaceData,
    }),
    [
      liveData,
      role,
      me,
      api,
      signOut,
      live,
      lang,
      toggleLanguage,
      t,
      profile,
      prefs,
      updateProfile,
      updatePrefs,
      page,
      navigate,
      selectedCourseId,
      courseTab,
      selectedBuildingId,
      activeChatThread,
      searchOpen,
      searchQuery,
      toastMessage,
      showToast,
      addPetition,
      updatePetitionStatus,
      unreadCount,
      markAllNotificationsRead,
      markNotificationRead,
      exportWorkspaceData,
    ]
  );

  return <CohortContext.Provider value={value}>{children}</CohortContext.Provider>;
}

export function useCohort() {
  const ctx = useContext(CohortContext);
  if (!ctx) throw new Error('useCohort must be used within CohortProvider');
  return ctx;
}
