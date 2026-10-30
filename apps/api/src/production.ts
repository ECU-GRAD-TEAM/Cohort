import { createRemoteJWKSet } from "jose";
import type { FastifyInstance } from "fastify";
import { buildApp } from "./app.ts";
import { createTokenVerifier } from "./auth.ts";
import type { Config } from "./config.ts";
import { createPrisma } from "./db.ts";

/**
 * The API as it runs outside tests: connected as `config.databaseUrl`, trusting the Supabase
 * project's published signing keys, and logging. Closing the app disconnects Prisma.
 */
export async function buildProductionApp(config: Config): Promise<FastifyInstance> {
  const prisma = createPrisma(config.databaseUrl);
  const app = await buildApp({
    prisma,
    verifyToken: createTokenVerifier({
      getKey: createRemoteJWKSet(config.jwksUrl),
      issuer: config.issuer,
      audience: config.audience,
    }),
    corsOrigin: config.corsOrigin,
    logger: true,
  });
  app.addHook("onClose", async () => {
    await prisma.$disconnect();
  });
  return app;
}
