import { jwtVerify, type JWTVerifyGetKey } from "jose";
import { z } from "zod";

/** The verified claims of a Supabase access token. */
export type AuthClaims = {
  sub: string;
  role: "authenticated";
  email?: string;
  [claim: string]: unknown;
};

/**
 * A token that is missing, malformed, expired, forged or not for a signed-in user. The original
 * failure is kept as `cause` for logs; the message is generic and is never shown to clients.
 */
export class UnauthorizedError extends Error {
  constructor(cause: unknown) {
    super("Unauthorized", { cause });
    this.name = "UnauthorizedError";
  }
}

export type TokenVerifier = (token: string) => Promise<AuthClaims>;

// Supabase signs with ES256 or RS256, depending on the project's signing key. Anything else, such
// as `none` or an HMAC keyed with a public value, is refused.
const ALGORITHMS = ["ES256", "RS256"];

// The `anon` key is also a valid Supabase JWT; only a signed-in user may reach the API.
const claimsSchema = z.looseObject({ sub: z.uuid(), role: z.literal("authenticated") });

/**
 * Verifies a Supabase access token against the project's published key set: signature, issuer,
 * audience and expiry, then that it belongs to a signed-in user (a UUID subject, the
 * `authenticated` role). Resolves to the full payload; rejects with `UnauthorizedError`.
 */
export function createTokenVerifier(options: {
  getKey: JWTVerifyGetKey;
  issuer: string;
  audience: string;
}): TokenVerifier {
  const { getKey, issuer, audience } = options;
  return async (token) => {
    try {
      const { payload } = await jwtVerify(token, getKey, {
        issuer,
        audience,
        algorithms: ALGORITHMS,
        requiredClaims: ["exp"],
      });
      return claimsSchema.parse(payload);
    } catch (error) {
      throw new UnauthorizedError(error);
    }
  };
}
