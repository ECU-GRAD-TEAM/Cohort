// Read through import.meta.env without throwing: tests import modules with no .env.
// The Supabase values may be empty here; they are validated where the client is created.
const env: Record<string, string | undefined> = import.meta.env;

export const webConfig = {
  supabaseUrl: env.VITE_SUPABASE_URL ?? "",
  supabasePublishableKey: env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "",
  apiUrl: env.VITE_API_URL || "http://localhost:3000",
};
