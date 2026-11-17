import React from 'react';
import { CheckCircle2 } from 'lucide-react';
import { AuthGate } from './auth/AuthGate';
import { CohortProvider, useCohort } from './context/CohortContext';
import { Header } from './components/layout/Header';
import { FloatingDock } from './components/layout/FloatingDock';
import { GlobalSearchModal } from './components/search/GlobalSearchModal';
import { DashboardPage } from './components/pages/DashboardPage';
import { CoursesPage } from './components/pages/CoursesPage';
import { SchedulePage } from './components/pages/SchedulePage';
import { MapPage } from './components/pages/MapPage';
import { RegistrationPage } from './components/pages/RegistrationPage';
import { GradingPage } from './components/pages/GradingPage';
import { AssistantPage } from './components/pages/AssistantPage';
import { MessagesPage } from './components/pages/MessagesPage';
import { ProfilePage } from './components/pages/ProfilePage';
import { AcademicAffairsPage } from './components/pages/AcademicAffairsPage';
import { SettingsPage } from './components/pages/SettingsPage';
import { NotificationsPage } from './components/pages/NotificationsPage';
import { SupportPage } from './components/pages/SupportPage';

const PAGE_MAP = {
  dashboard: DashboardPage,
  courses: CoursesPage,
  schedule: SchedulePage,
  map: MapPage,
  registration: RegistrationPage,
  grading: GradingPage,
  assistant: AssistantPage,
  messages: MessagesPage,
  profile: ProfilePage,
  'academic-affairs': AcademicAffairsPage,
  settings: SettingsPage,
  notifications: NotificationsPage,
  support: SupportPage,
};

function CohortShell() {
  const { page, toastMessage, prefs } = useCohort();
  const ActivePage = PAGE_MAP[page] || DashboardPage;

  return (
    <div
      className={`min-h-screen bg-[#FAF7F2] text-[#1A1715] antialiased ${
        prefs?.reduceMotion ? 'reduce-motion' : ''
      }`}
    >
      <Header />

      <main
        id="main-content"
        tabIndex={-1}
        className="mx-auto max-w-7xl px-4 sm:px-6 pt-5 pb-28 sm:pb-32 focus:outline-none"
      >
        <ActivePage />
      </main>

      <FloatingDock />
      <GlobalSearchModal />

      {toastMessage && (
        <div
          role="status"
          aria-live="polite"
          className="fixed bottom-24 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2 rounded-2xl bg-[#1A1715] text-[#FFFACD] px-4 py-2.5 text-xs sm:text-sm font-semibold shadow-xl border border-[#B81104]/40 max-w-[92vw]"
        >
          <CheckCircle2 className="w-4 h-4 text-[#FFFACD] shrink-0" aria-hidden="true" />
          <span>{toastMessage}</span>
        </div>
      )}
    </div>
  );
}

export default function App() {
  return (
    <AuthGate>
      <CohortProvider>
        <CohortShell />
      </CohortProvider>
    </AuthGate>
  );
}
