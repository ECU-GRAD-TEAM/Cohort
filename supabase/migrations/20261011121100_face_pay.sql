-- Face Pay (optional stage 5, spec §5.11). Identity and consent live in app; face
-- templates live in the biometric schema, which only the separate matching service
-- (market_biometric) may enter. The two sides share nothing but a non-reversible
-- subject token (an HMAC computed by the backend), as PDPL Law 151/2020 requires.

-- ---------------------------------------------------------------------------
-- Identity side
-- ---------------------------------------------------------------------------

create table app.face_pay_enrollments (
  id                    uuid primary key default gen_random_uuid(),
  customer_id           uuid not null references app.customers (id),
  subject_token         text not null unique check (subject_token ~ '^[0-9a-f]{64}$'),
  payment_method_id     uuid not null,
  status                text not null default 'active' check (status in ('active', 'paused', 'revoked')),
  consent_version       text not null,
  consented_at          timestamptz not null default now(),
  per_transaction_limit numeric(14,2) check (per_transaction_limit > 0),
  daily_limit           numeric(14,2) check (daily_limit > 0),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  revoked_at            timestamptz,
  check ((status = 'revoked') = (revoked_at is not null)),
  foreign key (customer_id, payment_method_id) references app.customer_payment_methods (customer_id, id)
);
comment on column app.face_pay_enrollments.subject_token is 'HMAC of the customer computed by the backend; the only link to biometric.face_templates.';

create trigger face_pay_enrollments_updated_at before update on app.face_pay_enrollments
  for each row execute function app.set_updated_at();

alter table app.sale_payments
  add constraint sale_payments_face_pay_enrollment_fkey
  foreign key (face_pay_enrollment_id) references app.face_pay_enrollments (id);

-- Resolves a matched token to the card to charge, inside the enrollment's limits
-- (daily limit counted from midnight Cairo time). Tills and staff only.
create function app.resolve_face_pay(p_subject_token text, p_amount numeric)
returns table (enrollment_id uuid, customer_id uuid, payment_method_id uuid, provider text, provider_token text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app.is_internal() then
    raise exception 'face pay resolution needs a till or staff context' using errcode = '42501';
  end if;

  return query
    select e.id, e.customer_id, pm.id, pm.provider, pm.provider_token
      from app.face_pay_enrollments e
      join app.customer_payment_methods pm
        on pm.id = e.payment_method_id and pm.customer_id = e.customer_id and pm.revoked_at is null
     where e.subject_token = p_subject_token
       and e.status = 'active'
       and (e.per_transaction_limit is null or p_amount <= e.per_transaction_limit)
       and (e.daily_limit is null
            or p_amount + coalesce((
                 select sum(sp.amount)
                   from app.sale_payments sp
                  where sp.face_pay_enrollment_id = e.id
                    and sp.status in ('authorized', 'captured')
                    and sp.created_at >= (date_trunc('day', now() at time zone 'Africa/Cairo') at time zone 'Africa/Cairo')
               ), 0) <= e.daily_limit);
end
$$;

alter table app.face_pay_enrollments enable row level security;

create policy face_pay_enrollments_self on app.face_pay_enrollments for all
  using (customer_id = (select app.current_customer_id()))
  with check (customer_id = (select app.current_customer_id()));

grant select, insert, update on app.face_pay_enrollments to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;

-- ---------------------------------------------------------------------------
-- Biometric side
-- ---------------------------------------------------------------------------

create table biometric.face_templates (
  id            uuid primary key default gen_random_uuid(),
  subject_token text not null check (subject_token ~ '^[0-9a-f]{64}$'),
  embedding     extensions.vector(128) not null,
  model_version text not null default 'facenet-128',
  quality_score numeric(5,4) check (quality_score between 0 and 1),
  created_at    timestamptz not null default now()
);
comment on table biometric.face_templates is 'FaceNet 128-D embeddings (never photos). No customer identity: only the subject token.';
create index face_templates_embedding_idx on biometric.face_templates using hnsw (embedding extensions.vector_l2_ops);
create index face_templates_subject_idx on biometric.face_templates (subject_token);

-- 1:K match: nearest templates, accepted at squared L2 distance <= 1.10 (proposal §6.2).
create function biometric.match_face(
  p_embedding            extensions.vector(128),
  p_max_squared_distance float8 default 1.10,
  p_limit                int default 3
) returns table (subject_token text, squared_distance float8)
language sql
stable
set search_path = pg_catalog, extensions
as $$
  select m.subject_token, m.distance * m.distance
    from (select t.subject_token, t.embedding <-> p_embedding as distance
            from biometric.face_templates t
           order by t.embedding <-> p_embedding
           limit p_limit) m
   where m.distance * m.distance <= p_max_squared_distance
   order by m.distance
$$;

-- Right to erasure: removes every template of a subject.
create function biometric.delete_subject(p_subject_token text) returns integer
language sql
as $$
  with deleted as (
    delete from biometric.face_templates t where t.subject_token = p_subject_token returning 1
  )
  select count(*)::int from deleted
$$;

alter table biometric.face_templates enable row level security;
create policy face_templates_matching_service on biometric.face_templates for all
  to market_biometric using (true) with check (true);

grant select, insert, delete on biometric.face_templates to market_biometric;
revoke execute on all functions in schema biometric from public;
grant execute on all functions in schema biometric to market_biometric;
