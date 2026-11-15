import { errors, jwtVerify, type JWTVerifyGetKey } from "jose";
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
 * failure, when there is one, is kept as `cause` for logs; the message is generic and is never
 * shown to clients.
 */
export class UnauthorizedError extends Error {
  constructor(cause?: unknown) {
    super("Unauthorized", { cause });
    this.name = "UnauthorizedError";
  }
}

/**
 * The key set needed to check a token could not be fetched or read (a timeout, a network error, a
 * malformed answer). Nothing is wrong with the token, so this is not an `UnauthorizedError`: a 401
 * signs the user out, and a brief outage on Supabase's side must not do that. The original failure
 * is kept as `cause` for logs.
 */
export class KeySetUnavailableError extends Error {
  constructor(cause?: unknown) {
    super("The signing keys could not be loaded", { cause });
    this.name = "KeySetUnavailableError";
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
 * `authenticated` role). Resolves to the full payload and rejects with `UnauthorizedError` for any
 * fault of the token, including a `kid` the key set does not list. It rejects with
 * `KeySetUnavailableError` when the key set itself cannot be loaded.
 */
export function createTokenVerifier(options: {
  getKey: JWTVerifyGetKey;
  issuer: string;
  audience: string;
}): TokenVerifier {
  const { issuer, audience } = options;
  // A key set that has no key for the token's `kid` is the token's fault. Any other failure of the
  // key set is not.
  const getKey: JWTVerifyGetKey = async (header, jws) => {
    try {
      return await options.getKey(header, jws);
    } catch (error) {
      if (error instanceof errors.JWKSNoMatchingKey || error instanceof errors.JWKSMultipleMatchingKeys) {
        throw error;
      }
      throw new KeySetUnavailableError(error);
    }
  };
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
      if (error instanceof KeySetUnavailableError) throw error;
      throw new UnauthorizedError(error);
    }
  };
}
