import { expect, it } from "vitest";
import { loadConfig } from "../src/config.ts";

it("derives the Supabase key set and issuer", () => {
  const c = loadConfig({ DATABASE_URL: "postgresql://cohort_api@db/x", SUPABASE_URL: "https://gejismdqvjuygtxibdhs.supabase.co" });
  expect(c.jwksUrl.href).toBe("https://gejismdqvjuygtxibdhs.supabase.co/auth/v1/.well-known/jwks.json");
  expect(c.issuer).toBe("https://gejismdqvjuygtxibdhs.supabase.co/auth/v1");
  expect([c.port, c.host, c.corsOrigin]).toEqual([3000, "127.0.0.1", "http://localhost:5173"]);
});

it("refuses to start without a database URL", () => {
  expect(() => loadConfig({ SUPABASE_URL: "https://x.supabase.co" })).toThrow();
});

it.each(["http://127.0.0.1:54321", "http://localhost:54321", "https://x.supabase.co/"])(
  "accepts the Supabase URL %s",
  (supabaseUrl) => {
    const c = loadConfig({ DATABASE_URL: "postgresql://cohort_api@db/x", SUPABASE_URL: supabaseUrl });
    expect(c.jwksUrl.pathname).toBe("/auth/v1/.well-known/jwks.json");
    expect(c.issuer).toBe(`${new URL(supabaseUrl).origin}/auth/v1`);
  },
);

it.each(["ftp://x.supabase.co", "javascript:alert(1)", "not a url"])("rejects the Supabase URL %s", (supabaseUrl) => {
  expect(() => loadConfig({ DATABASE_URL: "postgresql://cohort_api@db/x", SUPABASE_URL: supabaseUrl })).toThrow();
});
