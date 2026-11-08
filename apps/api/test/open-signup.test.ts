import { randomUUID } from "node:crypto";
import { afterAll, expect, it } from "vitest";
import { closeOwnerPool, withOwnerTransaction } from "./support/db.ts";

type Query = <R>(sql: string, params?: unknown[]) => Promise<R[]>;

afterAll(closeOwnerPool);

// Each test runs in a rolled-back transaction, so the open university never reaches other test
// files (me.test.ts relies on unlinked accounts).
function scenario(run: (h: Helpers) => Promise<void>) {
  return () =>
    withOwnerTransaction(async (query) => {
      let counter = 0;
      await run({
        university: async (open: boolean, status = "active") => {
          const id = randomUUID();
          await query(
            `insert into public.tenants (id, slug, name, data_region, status, open_signup)
             values ($1, $2, $3, 'eu-west-1', $4, $5)`,
            [id, `t-${id.slice(0, 8)}`, `University ${id.slice(0, 8)}`, status, open],
          );
          return id;
        },
        signUp: async (appMeta, userMeta) => {
          const id = randomUUID();
          await query(
            `insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
             values ($1, $2, $3::jsonb, $4::jsonb)`,
            [id, `Nadia-${counter++}@Example.TEST`, JSON.stringify(appMeta), JSON.stringify(userMeta)],
          );
          return id;
        },
        linked: async (id) => {
          const rows = await query<{
            tenant_id: string;
            user_type: string;
            email: string;
            display_name: string;
          }>(
            `select u.tenant_id, u.user_type, u.email, p.display_name
             from public.users u join public.person_profiles p on p.user_id = u.id
             where u.id = $1`,
            [id],
          );
          const roles = await query<{ key: string }>(
            `select r.key from public.user_roles ur join public.roles r on r.id = ur.role_id
             where ur.user_id = $1 order by r.key`,
            [id],
          );
          return { account: rows[0], roles: roles.map((r) => r.key) };
        },
        query,
      });
    });
}

type Helpers = {
  university: (open: boolean, status?: string) => Promise<string>;
  signUp: (appMeta: object, userMeta: object) => Promise<string>;
  linked: (id: string) => Promise<{
    account: { tenant_id: string; user_type: string; email: string; display_name: string } | undefined;
    roles: string[];
  }>;
  query: Query;
};

it("joins the open university as a student", scenario(async (h) => {
  const open = await h.university(true);
  const id = await h.signUp({}, { full_name: "Nadia New" });
  const { account, roles } = await h.linked(id);
  expect(account?.tenant_id).toBe(open);
  expect(account?.user_type).toBe("student");
  expect(account?.email).toMatch(/^nadia-\d+@example\.test$/);
  expect(account?.display_name).toBe("Nadia New");
  expect(roles).toEqual(["student"]);
}));

it("ignores university details sent as user metadata", scenario(async (h) => {
  const open = await h.university(true);
  const other = await h.university(false);
  const id = await h.signUp({}, { tenant_id: other, user_type: "administrator", full_name: "Mal" });
  const { account, roles } = await h.linked(id);
  expect(account?.tenant_id).toBe(open);
  expect(account?.user_type).toBe("student");
  expect(roles).toEqual(["student"]);
}));

it("leaves the account unlinked when no university is open", scenario(async (h) => {
  await h.university(false);
  const id = await h.signUp({}, {});
  expect((await h.linked(id)).account).toBeUndefined();
}));

it("leaves the account unlinked when the open university is suspended", scenario(async (h) => {
  await h.university(true, "suspended");
  const id = await h.signUp({}, {});
  expect((await h.linked(id)).account).toBeUndefined();
}));

it("keeps university-created accounts as they are", scenario(async (h) => {
  await h.university(true);
  const other = await h.university(false);
  const id = await h.signUp({ tenant_id: other, user_type: "teaching_staff" }, {});
  const { account } = await h.linked(id);
  expect(account?.tenant_id).toBe(other);
  expect(account?.user_type).toBe("teaching_staff");
}));

it("keeps partial university details unlinked", scenario(async (h) => {
  const open = await h.university(true);
  const id = await h.signUp({ tenant_id: open }, {});
  expect((await h.linked(id)).account).toBeUndefined();
}));

it("allows only one open university", scenario(async (h) => {
  await h.university(true);
  await expect(h.university(true)).rejects.toMatchObject({ code: "23505" });
}));
