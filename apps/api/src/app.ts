import type { ApiErrorBody } from "@cohort/contracts";
import cors from "@fastify/cors";
import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import {
  hasZodFastifySchemaValidationErrors,
  serializerCompiler,
  validatorCompiler,
} from "fastify-type-provider-zod";
import { UnauthorizedError, type AuthClaims, type TokenVerifier } from "./auth.ts";
import { withUserContext, type Tx } from "./db.ts";
import { ApiError, databaseErrorToApiError, INTERNAL_MESSAGE } from "./errors.ts";
import type { PrismaClient } from "./generated/prisma/client.ts";
import { catalogueRoutes } from "./routes/catalogue.ts";
import { enrollmentRoutes } from "./routes/enrollments.ts";
import { gradeRoutes } from "./routes/grades.ts";
import { meRoutes } from "./routes/me.ts";

declare module "fastify" {
  interface FastifyRequest {
    /** The verified claims of the caller. Set on every route in the authenticated scope. */
    user: AuthClaims;
    /**
     * Runs `fn` in a transaction as the caller, so row-level security applies. Every database
     * call in a route goes through it. A transaction has one connection: await its queries one
     * at a time. Overlapping queries, from `Promise.all` or from selecting several relations in
     * one Prisma query, make `pg` warn that this is deprecated.
     */
    withDb<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
  }
}

export type AppDependencies = {
  prisma: PrismaClient;
  verifyToken: TokenVerifier;
  corsOrigin: string;
  logger?: boolean;
};

const UNAUTHORIZED_MESSAGE = "Sign in to continue.";

/** The token of an `Authorization: Bearer <token>` header. */
function bearerToken(header: string | undefined): string {
  const token = header ? /^Bearer\s+(\S+)$/i.exec(header)?.[1] : undefined;
  if (!token) throw new UnauthorizedError();
  return token;
}

function sendError(reply: FastifyReply, error: ApiError) {
  const body: ApiErrorBody = { error: { code: error.code, message: error.message } };
  return reply.code(error.statusCode).send(body);
}

export async function buildApp(deps: AppDependencies): Promise<FastifyInstance> {
  const app = Fastify({ logger: deps.logger ?? false });

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  await app.register(cors, { origin: deps.corsOrigin, methods: ["GET", "POST", "DELETE"] });

  app.setNotFoundHandler((_request, reply) => sendError(reply, new ApiError(404, "not_found", "Not found.")));

  app.setErrorHandler((error, request, reply) => {
    const apiError = toApiError(error);
    // The client learns nothing about a 500, so the log is the only record of what happened.
    if (apiError.statusCode >= 500) request.log.error({ err: error }, "request failed");
    return sendError(reply, apiError);
  });

  app.get("/health", async () => ({ status: "ok" }));

  // Every route registered in this scope belongs to a signed-in user. Add each route plugin here.
  await app.register(async (scope) => {
    // Fastify wants a reference-typed decoration to start as null; the hook below sets it before any handler runs.
    scope.decorateRequest("user", null as unknown as AuthClaims);
    scope.decorateRequest("withDb", function (fn) {
      return withUserContext(deps.prisma, this.user, fn);
    });

    scope.addHook("onRequest", async (request, reply) => {
      try {
        request.user = await deps.verifyToken(bearerToken(request.headers.authorization));
      } catch (error) {
        if (!(error instanceof UnauthorizedError)) throw error;
        request.log.info({ err: error }, "access token rejected");
        return sendError(reply, new ApiError(401, "unauthorized", UNAUTHORIZED_MESSAGE));
      }
    });

    await scope.register(meRoutes);
    await scope.register(catalogueRoutes);
    await scope.register(enrollmentRoutes);
    await scope.register(gradeRoutes);
  });

  return app;
}

/** Decides what the client is told, in this order: validation, our own errors, the database, other 4xx, everything else. */
function toApiError(error: unknown): ApiError {
  if (hasZodFastifySchemaValidationErrors(error)) {
    return new ApiError(400, "invalid_request", error.message);
  }
  if (error instanceof ApiError) return error;
  const fromDatabase = databaseErrorToApiError(error);
  if (fromDatabase) return fromDatabase;
  // Fastify's own refusals, such as a body that is not valid JSON.
  if (
    error instanceof Error &&
    "statusCode" in error &&
    typeof error.statusCode === "number" &&
    error.statusCode >= 400 &&
    error.statusCode < 500
  ) {
    return new ApiError(error.statusCode, "invalid_request", error.message);
  }
  return new ApiError(500, "internal", INTERNAL_MESSAGE);
}
