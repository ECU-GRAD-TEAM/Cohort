import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  SignJWT,
  type CryptoKey,
  type JWK,
  type JWTPayload,
} from "jose";
import { createTokenVerifier, type TokenVerifier } from "../../src/auth.ts";

export const TEST_ISSUER = "https://test.supabase.co/auth/v1";

const KEY_ID = "test-key";

export type TestAuth = {
  /** The verifier under test, trusting only this test auth's published key. */
  verifyToken: TokenVerifier;
  /** A valid access token for `sub`; `overrides` replace or add claims (`exp`, `aud`, `iss`, `role`, `sub`...). */
  tokenFor(sub: string, overrides?: JWTPayload): Promise<string>;
  /** A well-formed token for `sub` signed by a key the verifier has never been given. */
  foreignTokenFor(sub: string): Promise<string>;
};

/**
 * An ES256 key pair published as a local key set, standing in for Supabase's JWKS endpoint, and a
 * second key pair that is not published.
 */
export async function createTestAuth(): Promise<TestAuth> {
  const trusted = await generateKeyPair("ES256");
  const unknown = await generateKeyPair("ES256");

  const publicJwk: JWK = { ...(await exportJWK(trusted.publicKey)), kid: KEY_ID, alg: "ES256", use: "sig" };
  const verifyToken = createTokenVerifier({
    getKey: createLocalJWKSet({ keys: [publicJwk] }),
    issuer: TEST_ISSUER,
    audience: "authenticated",
  });

  const sign = (privateKey: CryptoKey, sub: string, overrides: JWTPayload = {}) =>
    new SignJWT({
      iss: TEST_ISSUER,
      aud: "authenticated",
      role: "authenticated",
      exp: Math.floor(Date.now() / 1000) + 3600,
      sub,
      ...overrides,
    })
      .setProtectedHeader({ alg: "ES256", kid: KEY_ID })
      .sign(privateKey);

  return {
    verifyToken,
    tokenFor: (sub, overrides) => sign(trusted.privateKey, sub, overrides),
    // Same `kid` as the real key, so the key set offers the trusted public key and only the
    // signature check can reject the token.
    foreignTokenFor: (sub) => sign(unknown.privateKey, sub),
  };
}
