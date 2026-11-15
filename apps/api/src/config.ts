import { z } from "zod";

export type Config = {
  databaseUrl: string;
  supabaseUrl: string;
  /** Where Supabase publishes the public keys that sign its access tokens. */
  jwksUrl: URL;
  issuer: string;
  audience: "authenticated";
  corsOrigin: string;
  port: number;
  host: string;
  studentAiServiceUrl?: string;
  studentAiInternalKey?: string;
};

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  SUPABASE_URL: z.url({ protocol: /^https?$/ }),
  CORS_ORIGIN: z.string().min(1).default("http://localhost:5173"),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  HOST: z.string().min(1).default("127.0.0.1"),
  STUDENT_AI_SERVICE_URL: z.url({ protocol: /^https?$/ }).optional(),
  STUDENT_AI_INTERNAL_KEY: z.string().min(32).optional(),
});

/** Reads and validates the API's environment. Throws if a required value is missing or invalid. */
export function loadConfig(env: Record<string, string | undefined>): Config {
  const parsed = envSchema.parse(env);
  return {
    databaseUrl: parsed.DATABASE_URL,
    supabaseUrl: parsed.SUPABASE_URL,
    jwksUrl: new URL("/auth/v1/.well-known/jwks.json", parsed.SUPABASE_URL),
    issuer: new URL("/auth/v1", parsed.SUPABASE_URL).href,
    audience: "authenticated",
    corsOrigin: parsed.CORS_ORIGIN,
    port: parsed.PORT,
    host: parsed.HOST,
    studentAiServiceUrl: parsed.STUDENT_AI_SERVICE_URL,
    studentAiInternalKey: parsed.STUDENT_AI_INTERNAL_KEY,
  };
}
