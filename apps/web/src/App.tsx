import { Route, Routes } from "react-router";
import { AppShell } from "./AppShell.tsx";
import { RequireAuth } from "./auth/RequireAuth.tsx";
import { DashboardPage } from "./pages/DashboardPage.tsx";
import { LoginPage } from "./pages/LoginPage.tsx";
import { RegistrationPage } from "./pages/RegistrationPage.tsx";
import { SignUpPage } from "./pages/SignUpPage.tsx";
import { AssignmentsPreview } from "./previews/AssignmentsPreview.tsx";
import { AssistantPreview } from "./previews/AssistantPreview.tsx";
import { CampusPreview } from "./previews/CampusPreview.tsx";
import { CoursesPreview } from "./previews/CoursesPreview.tsx";
import { MessagesPreview } from "./previews/MessagesPreview.tsx";
import { SchedulePreview } from "./previews/SchedulePreview.tsx";
import { SupportPreview } from "./previews/SupportPreview.tsx";

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/signup" element={<SignUpPage />} />
      <Route
        element={
          <RequireAuth>
            <AppShell />
          </RequireAuth>
        }
      >
        <Route index element={<DashboardPage />} />
        <Route path="register" element={<RegistrationPage />} />
        <Route path="courses" element={<CoursesPreview />} />
        <Route path="schedule" element={<SchedulePreview />} />
        <Route path="assignments" element={<AssignmentsPreview />} />
        <Route path="messages" element={<MessagesPreview />} />
        <Route path="support" element={<SupportPreview />} />
        <Route path="campus" element={<CampusPreview />} />
        <Route path="assistant" element={<AssistantPreview />} />
      </Route>
    </Routes>
  );
}
