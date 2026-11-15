import { PrismaPg } from "@prisma/adapter-pg";
import type { AuthClaims } from "./auth.ts";
import { Prisma, PrismaClient } from "./generated/prisma/client.ts";

/** A Prisma client bound to one database transaction. */
export type Tx = Prisma.TransactionClient;

export function createPrisma(databaseUrl: string): PrismaClient {
  return new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
}

/**
 * Runs `fn` in a transaction under the caller's identity. The API connects as `cohort_api`, which
 * holds no privileges of its own. The transaction sets the claims the database reads through
 * auth.uid(), then switches to `authenticated`, so every statement in `fn` passes through
 * row-level security as that user. Both settings last only until the transaction ends.
 */
export function withUserContext<T>(
  prisma: PrismaClient,
  claims: AuthClaims,
  fn: (tx: Tx) => Promise<T>,
): Promise<T> {
  return prisma.$transaction(async (tx) => {
    await tx.$queryRaw`select set_config('request.jwt.claims', ${JSON.stringify(claims)}, true)`;
    await tx.$executeRaw`set local role authenticated`;
    return fn(tx);
  });
}
