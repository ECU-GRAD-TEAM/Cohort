import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { z } from "zod";
import { ApiError } from "../errors.ts";

const Body = z.object({
  message: z.string().trim().min(1).max(12_000),
  history: z.array(z.object({ role: z.enum(["user", "assistant"]), content: z.string().min(1).max(12_000) })).max(20).default([]),
  language: z.enum(["auto", "en", "ar"]).default("auto"),
}).strict();
const Response = z.object({ answer: z.string(), language: z.string(), provider: z.string(), model: z.string(), latency_ms: z.number(), sources: z.array(z.string()), limitations: z.array(z.string()) });

export const studentAiRoutes: FastifyPluginAsync = async (app) => {
  app.withTypeProvider<ZodTypeProvider>().post("/student-ai/chat", {
    schema: { body: Body, response: { 200: Response } },
  }, async (request) => {
    const serviceUrl = process.env.STUDENT_AI_SERVICE_URL;
    const internalKey = process.env.STUDENT_AI_INTERNAL_KEY;
    if (!serviceUrl || !internalKey) throw new ApiError(503, "internal", "The student assistant is not configured.");
    // Identity is verified here. No client-supplied user/tenant id is forwarded or trusted.
    // Record/document retrieval is deliberately not wired until its access-scoped tools are implemented.
    let upstream: Response;
    try {
      upstream = await fetch(new URL("/v1/chat", serviceUrl), {
        method: "POST", headers: { "content-type": "application/json", "x-cohort-internal-key": internalKey },
        body: JSON.stringify({ message: request.body.message, history: request.body.history, language: request.body.language, context: [] }),
        signal: AbortSignal.timeout(50_000),
      });
    } catch {
      throw new ApiError(502, "internal", "The student assistant is temporarily unavailable.");
    }
    if (!upstream.ok) throw new ApiError(upstream.status === 401 ? 503 : 502, "internal", "The student assistant could not complete the request.");
    const data: unknown = await upstream.json();
    const parsed = Response.safeParse(data);
    if (!parsed.success) throw new ApiError(502, "internal", "The student assistant returned an invalid response.");
    return parsed.data;
  });
};
