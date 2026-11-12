import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { z } from "zod";
import { ApiError } from "../errors.ts";

const Body = z.object({
  message: z.string().trim().min(1).max(12_000),
  history: z.array(z.object({ role: z.enum(["user", "assistant"]), content: z.string().min(1).max(12_000) })).max(20).default([]),
  language: z.enum(["auto", "en", "ar"]).default("auto"),
}).strict();
const ResponseSchema = z.object({ answer: z.string(), language: z.string(), provider: z.string(), model: z.string(), latency_ms: z.number(), sources: z.array(z.string()), limitations: z.array(z.string()) });

export const studentAiRoutes: FastifyPluginAsync = async (app) => {
  app.withTypeProvider<ZodTypeProvider>().post("/student-ai/chat", {
    schema: { body: Body, response: { 200: ResponseSchema } },
  }, async (request) => {
    const serviceUrl = process.env.STUDENT_AI_SERVICE_URL;
    const internalKey = process.env.STUDENT_AI_INTERNAL_KEY;
    const authorization = request.headers.authorization;
    if (!serviceUrl || !internalKey) throw new ApiError(503, "internal", "The student assistant is not configured.");
    if (!authorization || !/^Bearer\s+\S+$/i.test(authorization)) {
      throw new ApiError(401, "unauthorized", "Sign in to continue.");
    }

    let upstream: globalThis.Response;
    try {
      upstream = await fetch(new URL("/v1/chat", serviceUrl), {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-cohort-internal-key": internalKey,
          authorization,
        },
        body: JSON.stringify({ message: request.body.message, history: request.body.history, language: request.body.language }),
        signal: AbortSignal.timeout(50_000),
      });
    } catch {
      throw new ApiError(502, "internal", "The student assistant is temporarily unavailable.");
    }
    if (!upstream.ok) {
      if (upstream.status === 401 || upstream.status === 403) {
        throw new ApiError(upstream.status, upstream.status === 401 ? "unauthorized" : "forbidden",
          upstream.status === 401 ? "Sign in to continue." : "The student assistant is available to student accounts only.");
      }
      throw new ApiError(502, "internal", "The student assistant could not complete the request.");
    }
    const data: unknown = await upstream.json();
    const parsed = ResponseSchema.safeParse(data);
    if (!parsed.success) throw new ApiError(502, "internal", "The student assistant returned an invalid response.");
    return parsed.data;
  });
};
