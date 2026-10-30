import { createRemoteJWKSet } from "jose";
import { buildApp } from "./app.ts";
import { createTokenVerifier } from "./auth.ts";
import { loadConfig } from "./config.ts";
import { createPrisma } from "./db.ts";

const config = loadConfig(process.env);
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

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => void app.close());
}

await app.listen({ port: config.port, host: config.host });
