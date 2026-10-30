import { afterEach, describe, expect, it, vi } from "vitest";

const loadConfig = async () => {
  vi.resetModules();
  return (await import("./config.ts")).webConfig;
};

describe("webConfig", () => {
  afterEach(() => vi.unstubAllEnvs());

  it("imports without any environment and falls back to the local API", async () => {
    vi.stubEnv("VITE_SUPABASE_URL", undefined);
    vi.stubEnv("VITE_SUPABASE_PUBLISHABLE_KEY", undefined);
    vi.stubEnv("VITE_API_URL", undefined);
    await expect(loadConfig()).resolves.toEqual({
      supabaseUrl: "",
      supabasePublishableKey: "",
      apiUrl: "http://localhost:3000",
    });
  });

  it("reads the configured values", async () => {
    vi.stubEnv("VITE_SUPABASE_URL", "https://example.supabase.co");
    vi.stubEnv("VITE_SUPABASE_PUBLISHABLE_KEY", "sb_publishable_key");
    vi.stubEnv("VITE_API_URL", "https://api.example.edu");
    await expect(loadConfig()).resolves.toEqual({
      supabaseUrl: "https://example.supabase.co",
      supabasePublishableKey: "sb_publishable_key",
      apiUrl: "https://api.example.edu",
    });
  });
});
