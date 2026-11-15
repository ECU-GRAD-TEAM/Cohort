import { createClient } from "@supabase/supabase-js";
import { webConfig } from "../config.ts";

// Only main.tsx imports this module, so tests never need Supabase settings.
if (!webConfig.supabaseUrl || !webConfig.supabasePublishableKey) {
  throw new Error(
    "Missing Supabase settings. Set VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY in apps/web/.env (see apps/web/.env.example).",
  );
}

export const supabase = createClient(webConfig.supabaseUrl, webConfig.supabasePublishableKey);
