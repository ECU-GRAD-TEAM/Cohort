import { Route, Routes } from "react-router";
import { AppShell } from "./AppShell.tsx";
import { RequireAuth } from "./auth/RequireAuth.tsx";
import { DashboardPage } from "./pages/DashboardPage.tsx";
import { LoginPage } from "./pages/LoginPage.tsx";
import { RegistrationPage } from "./pages/RegistrationPage.tsx";
import { SignUpPage } from "./pages/SignUpPage.tsx";

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
      </Route>
    </Routes>
  );
}
