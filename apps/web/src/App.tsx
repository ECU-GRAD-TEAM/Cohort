import { Route, Routes } from "react-router";
import { AppShell } from "./AppShell.tsx";
import { RequireAuth } from "./auth/RequireAuth.tsx";
import { DashboardPage } from "./pages/DashboardPage.tsx";
import { LoginPage } from "./pages/LoginPage.tsx";
import { RegistrationPage } from "./pages/RegistrationPage.tsx";
import { StudentAiPage } from "./pages/StudentAiPage.tsx";

export function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        element={
          <RequireAuth>
            <AppShell />
          </RequireAuth>
        }
      >
        <Route index element={<DashboardPage />} />
        <Route path="register" element={<RegistrationPage />} />
        <Route path="student-assistant" element={<StudentAiPage />} />
      </Route>
    </Routes>
  );
}
