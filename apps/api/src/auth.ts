/** The verified claims of a Supabase access token. */
export type AuthClaims = {
  sub: string;
  role: "authenticated";
  email?: string;
  [claim: string]: unknown;
};
