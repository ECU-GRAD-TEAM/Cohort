import { afterEach, describe, expect, it, vi } from "vitest";

const loadSupabase = async () => {
  vi.resetModules();
  return import("./supabase.ts");
};

describe("supabase client", () => {
  afterEach(() => vi.unstubAllEnvs());

  it("names both settings when neither is set", async () => {
    vi.stubEnv("VITE_SUPABASE_URL", undefined);
    vi.stubEnv("VITE_SUPABASE_PUBLISHABLE_KEY", undefined);
    await expect(loadSupabase()).rejects.toThrow(/VITE_SUPABASE_URL.*VITE_SUPABASE_PUBLISHABLE_KEY/);
  });

  it("names both settings when only one is set", async () => {
    vi.stubEnv("VITE_SUPABASE_URL", "https://example.supabase.co");
    vi.stubEnv("VITE_SUPABASE_PUBLISHABLE_KEY", "");
    await expect(loadSupabase()).rejects.toThrow(/VITE_SUPABASE_URL.*VITE_SUPABASE_PUBLISHABLE_KEY/);
  });
});
