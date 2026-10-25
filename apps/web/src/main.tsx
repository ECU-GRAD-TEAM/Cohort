import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router";
import { App } from "./App.tsx";
import { AuthProvider } from "./auth/AuthProvider.tsx";
import { webConfig } from "./config.ts";
import { ApiError, createApiClient } from "./lib/api.ts";
import { ApiProvider } from "./lib/ApiContext.tsx";
import { supabase } from "./lib/supabase.ts";

// The API's token for the current request, or null when there is none. Never throws: the API
// answers 401 when it gets no token, which signs the user out.
async function getAccessToken(): Promise<string | null> {
  try {
    const { data, error } = await supabase.auth.getSession();
    if (error) return null;
    return data.session?.access_token ?? null;
  } catch {
    return null;
  }
}

const apiClient = createApiClient({
  baseUrl: webConfig.apiUrl,
  getAccessToken,
  onUnauthorized: () => void supabase.auth.signOut(),
});

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // A 4xx answer (no university, expired session) will not change on a retry, so show it at once.
      retry: (failureCount, error) =>
        failureCount < 2 && !(error instanceof ApiError && error.status >= 400 && error.status < 500),
    },
  },
});

const container = document.getElementById("root");
if (!container) throw new Error("The page has no #root element.");

createRoot(container).render(
  <StrictMode>
    <BrowserRouter>
      <QueryClientProvider client={queryClient}>
        <AuthProvider auth={supabase.auth}>
          <ApiProvider client={apiClient}>
            <App />
          </ApiProvider>
        </AuthProvider>
      </QueryClientProvider>
    </BrowserRouter>
  </StrictMode>,
);
