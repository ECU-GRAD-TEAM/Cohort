import { MeResponse } from "@cohort/contracts";
import type { FastifyPluginAsync } from "fastify";
import type { ZodTypeProvider } from "fastify-type-provider-zod";
import { ApiError } from "../errors.ts";

export const meRoutes: FastifyPluginAsync = async (app) => {
  app.withTypeProvider<ZodTypeProvider>().get(
    "/me",
    { schema: { response: { 200: MeResponse } } },
    async (request) => {
      const { sub } = request.user;
      // One query at a time: a transaction has a single connection (see `withDb`).
      const found = await request.withDb(async (tx) => {
        // By id, because row-level security also lets an account manager read other users.
        const user = await tx.users.findUnique({
          where: { id: sub },
          select: { id: true, email: true, user_type: true, tenants: { select: { id: true, name: true } } },
        });
        if (!user) return null;
        const profile = await tx.person_profiles.findUnique({
          where: { user_id: sub },
          select: { display_name: true },
        });
        // Like the database's own role checks, skip assignments that have expired.
        const roles = await tx.roles.findMany({
          where: {
            user_roles: {
              some: { user_id: sub, OR: [{ expires_at: null }, { expires_at: { gt: new Date() } }] },
            },
          },
          select: { key: true },
          orderBy: { key: "asc" },
        });
        return { user, profile, roles };
      });
      if (!found) {
        throw new ApiError(403, "forbidden", "Your account is not linked to a university yet.");
      }

      const { user, profile, roles } = found;
      return {
        id: user.id,
        email: user.email,
        userType: user.user_type,
        // Sign-up always creates a profile; the email only guards against a missing one.
        displayName: profile?.display_name ?? user.email,
        tenant: user.tenants,
        roles: roles.map((role) => role.key),
      };
    },
  );
};
