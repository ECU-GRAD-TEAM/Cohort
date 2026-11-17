import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

/** Set when the build has no Supabase settings, so sign-in cannot work at all. */
export const configError =
  !url || !key
    ? 'This build is missing its Supabase settings (VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY).'
    : null;

/** The browser's Supabase client: it keeps the session in local storage and refreshes it. */
export const supabase = configError
  ? null
  : createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
