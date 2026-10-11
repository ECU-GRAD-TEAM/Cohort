-- Audit chain and loss prevention (T9, spec §5.8).
--
-- Every override, refund, void, drawer opening and back-office change is a block in an
-- append-only SHA-256 chain: hash = sha256(seq || prev_hash || payload), as in the T9
-- proof of concept. Each till keeps its own chain (chain_id = device id, computed on the
-- till); back-office actions go to the tenant's cloud chain (chain_id = tenant id).

-- ---------------------------------------------------------------------------
-- Audit chain
-- ---------------------------------------------------------------------------

create table app.audit_log (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references app.tenants (id),
  branch_id            uuid,
  chain_id             uuid not null,
  seq                  bigint not null check (seq >= 0),
  event_type           text not null check (event_type ~ '^[A-Z][A-Z_]*$'),
  actor_staff_id       uuid,
  approved_by_staff_id uuid,
  device_id            uuid,
  shift_id             uuid,
  payload              text not null,
  payload_json         jsonb generated always as (payload::jsonb) stored,
  prev_hash            text not null check (prev_hash ~ '^[0-9a-f]{64}$'),
  hash                 text not null check (hash ~ '^[0-9a-f]{64}$'),
  occurred_at          timestamptz not null default now(),
  recorded_at          timestamptz not null default now(),
  unique (chain_id, seq),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, actor_staff_id) references app.staff (tenant_id, id),
  foreign key (tenant_id, approved_by_staff_id) references app.staff (tenant_id, id),
  foreign key (tenant_id, device_id) references app.pos_devices (tenant_id, id),
  foreign key (tenant_id, shift_id) references app.cashier_shifts (tenant_id, id)
);
comment on column app.audit_log.payload is 'The exact canonical JSON text that was hashed. payload_json is derived from it for querying.';
create index audit_log_event_idx on app.audit_log (tenant_id, event_type, occurred_at);
create index audit_log_shift_idx on app.audit_log (shift_id) where shift_id is not null;

create table app.audit_checkpoints (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references app.tenants (id),
  chain_id         uuid not null,
  seq              bigint not null,
  hash             text not null check (hash ~ '^[0-9a-f]{64}$'),
  created_at       timestamptz not null default now(),
  anchored_at      timestamptz,
  anchor_reference text,
  unique (chain_id, seq),
  foreign key (chain_id, seq) references app.audit_log (chain_id, seq)
);
comment on table app.audit_checkpoints is 'Chain heads anchored outside the database (e.g. every 1,000 blocks) so a truncated tail can also be detected.';

create function app.audit_hash(p_seq bigint, p_prev_hash text, p_payload text) returns text
language sql
stable
as $$
  select encode(sha256(convert_to(p_seq::text || p_prev_hash || p_payload, 'UTF8')), 'hex')
$$;

-- Every block must continue its chain: right owner, next seq, previous hash, own hash.
create function app.verify_audit_append() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev record;
begin
  if new.chain_id <> new.tenant_id
     and (new.device_id is distinct from new.chain_id
          or not exists (select 1 from app.pos_devices d where d.id = new.chain_id and d.tenant_id = new.tenant_id)) then
    raise exception 'chain % does not belong to tenant %', new.chain_id, new.tenant_id;
  end if;

  if new.seq = 0 then
    if new.prev_hash <> repeat('0', 64) then
      raise exception 'a genesis block must link to 64 zeros';
    end if;
  else
    select a.hash, a.tenant_id into v_prev
      from app.audit_log a
     where a.chain_id = new.chain_id and a.seq = new.seq - 1;
    if not found then
      raise exception 'block % of chain % arrived before block %', new.seq, new.chain_id, new.seq - 1;
    end if;
    if v_prev.tenant_id <> new.tenant_id or new.prev_hash <> v_prev.hash then
      raise exception 'block % does not link to block % of chain %', new.seq, new.seq - 1, new.chain_id;
    end if;
  end if;

  if new.hash <> app.audit_hash(new.seq, new.prev_hash, new.payload) then
    raise exception 'block % of chain % does not match its content', new.seq, new.chain_id;
  end if;
  return new;
end
$$;

create trigger audit_log_verify_append before insert on app.audit_log
  for each row execute function app.verify_audit_append();
create trigger audit_log_append_only before update or delete on app.audit_log
  for each row execute function app.prevent_mutation();

-- Appends a back-office event to the current tenant's cloud chain.
create function app.append_audit(
  p_event_type  text,
  p_payload     jsonb,
  p_branch_id   uuid default null,
  p_approved_by uuid default null,
  p_shift_id    uuid default null
) returns app.audit_log
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant  uuid := app.current_tenant_id();
  v_genesis text := '{"event": "GENESIS_BLOCK"}';
  v_zero    text := repeat('0', 64);
  v_payload text := p_payload::text;
  v_last    app.audit_log;
  v_row     app.audit_log;
begin
  if v_tenant is null or not app.is_internal() then
    raise exception 'audit entries need an internal tenant context' using errcode = '42501';
  end if;
  if p_branch_id is not null and not (p_branch_id = any (app.accessible_branch_ids())) then
    raise exception 'branch % is outside the caller''s reach', p_branch_id using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_tenant::text, 0));

  select * into v_last from app.audit_log a where a.chain_id = v_tenant order by a.seq desc limit 1;
  if not found then
    insert into app.audit_log (tenant_id, chain_id, seq, event_type, payload, prev_hash, hash)
    values (v_tenant, v_tenant, 0, 'GENESIS_BLOCK', v_genesis, v_zero, app.audit_hash(0, v_zero, v_genesis))
    returning * into v_last;
  end if;

  insert into app.audit_log (tenant_id, branch_id, chain_id, seq, event_type, actor_staff_id,
                             approved_by_staff_id, device_id, shift_id, payload, prev_hash, hash)
  values (v_tenant, p_branch_id, v_tenant, v_last.seq + 1, p_event_type, app.current_staff_id(),
          p_approved_by, app.current_device_id(), p_shift_id, v_payload, v_last.hash,
          app.audit_hash(v_last.seq + 1, v_last.hash, v_payload))
  returning * into v_row;
  return v_row;
end
$$;

-- Recomputes a chain from its genesis block and reports the first broken block.
create function app.verify_audit_chain(p_chain_id uuid)
returns table (is_valid boolean, checked_count bigint, first_invalid_seq bigint, reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_block        record;
  v_expected_seq bigint := 0;
  v_prev_hash    text := repeat('0', 64);
  v_count        bigint := 0;
begin
  if app.current_tenant_id() is null or not app.is_internal() then
    raise exception 'chain verification needs an internal tenant context' using errcode = '42501';
  end if;
  if p_chain_id <> app.current_tenant_id()
     and not exists (select 1 from app.pos_devices d
                      where d.id = p_chain_id and d.tenant_id = app.current_tenant_id()) then
    raise exception 'chain % is not part of the current tenant', p_chain_id using errcode = '42501';
  end if;

  for v_block in
    select a.seq, a.prev_hash, a.payload, a.hash from app.audit_log a where a.chain_id = p_chain_id order by a.seq
  loop
    v_count := v_count + 1;
    if v_block.seq <> v_expected_seq then
      return query select false, v_count, v_block.seq, 'sequence gap'::text;
      return;
    end if;
    if v_block.prev_hash <> v_prev_hash then
      return query select false, v_count, v_block.seq, 'prev_hash mismatch'::text;
      return;
    end if;
    if v_block.hash <> app.audit_hash(v_block.seq, v_block.prev_hash, v_block.payload) then
      return query select false, v_count, v_block.seq, 'hash mismatch'::text;
      return;
    end if;
    v_prev_hash := v_block.hash;
    v_expected_seq := v_expected_seq + 1;
  end loop;

  return query select true, v_count, null::bigint, null::text;
end
$$;

alter table app.audit_log enable row level security;
alter table app.audit_checkpoints enable row level security;

create policy audit_log_read on app.audit_log for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal())
         and (branch_id is null or branch_id = any ((select app.accessible_branch_ids())::uuid[])));
create policy audit_log_insert on app.audit_log for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal())
              and (branch_id is null or branch_id = any ((select app.accessible_branch_ids())::uuid[])));

create policy audit_checkpoints_internal on app.audit_checkpoints for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));

grant select, insert on app.audit_log to market_backend;
grant select, insert on app.audit_checkpoints to market_backend;
grant update (anchored_at, anchor_reference) on app.audit_checkpoints to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;

-- ---------------------------------------------------------------------------
-- Loss prevention: exception-based flags per cashier shift (T9 §4.3)
-- ---------------------------------------------------------------------------

create table app.loss_prevention_settings (
  tenant_id                     uuid primary key references app.tenants (id),
  unlinked_refund_amount        numeric(14,2) not null default 50.00 check (unlinked_refund_amount >= 0),
  unlinked_refunds_per_hour     int not null default 3 check (unlinked_refunds_per_hour >= 0),
  void_amount_per_shift         numeric(14,2) not null default 200.00 check (void_amount_per_shift >= 0),
  manual_drawer_opens_per_shift int not null default 3 check (manual_drawer_opens_per_shift >= 0),
  updated_at                    timestamptz not null default now()
);
comment on table app.loss_prevention_settings is 'Per-tenant thresholds. Without a row the research defaults apply.';

create table app.fraud_flags (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  branch_id   uuid not null,
  shift_id    uuid,
  staff_id    uuid,
  rule        text not null check (rule in ('UNLINKED_REFUND_AMOUNT', 'UNLINKED_REFUND_FREQUENCY', 'VOID_AMOUNT',
                                            'POST_CLOSE_VOID', 'MANUAL_DRAWER_OPENS')),
  severity    text not null check (severity in ('low', 'medium', 'high')),
  subject_id  uuid not null,
  details     jsonb not null default '{}' check (jsonb_typeof(details) = 'object'),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'dismissed', 'confirmed')),
  detected_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  unique (rule, subject_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, shift_id) references app.cashier_shifts (tenant_id, id),
  foreign key (tenant_id, staff_id) references app.staff (tenant_id, id),
  foreign key (tenant_id, reviewed_by) references app.staff (tenant_id, id)
);
comment on column app.fraud_flags.subject_id is 'The sale (per-sale rules) or the shift (per-shift rules) the flag is about.';

create trigger loss_prevention_settings_updated_at before update on app.loss_prevention_settings
  for each row execute function app.set_updated_at();

-- Evaluates one shift and stores new flags; already-raised flags are not repeated.
create function app.detect_shift_exceptions(p_shift_id uuid) returns setof app.fraud_flags
language sql
as $$
  with shift as (
    select s.id, s.tenant_id, s.branch_id, s.staff_id from app.cashier_shifts s where s.id = p_shift_id
  ),
  cfg as (
    select coalesce(lp.unlinked_refund_amount, 50.00)       as refund_amount,
           coalesce(lp.unlinked_refunds_per_hour, 3)        as refunds_per_hour,
           coalesce(lp.void_amount_per_shift, 200.00)       as void_amount,
           coalesce(lp.manual_drawer_opens_per_shift, 3)    as drawer_opens
      from shift
      left join app.loss_prevention_settings lp on lp.tenant_id = shift.tenant_id
  ),
  unlinked as (
    select s.id, s.grand_total, s.occurred_at
      from app.sales s
     where s.shift_id = p_shift_id and s.sale_type = 'return' and s.original_sale_id is null
  ),
  candidates as (
    select 'UNLINKED_REFUND_AMOUNT'::text as rule, 'medium'::text as severity, u.id as subject_id,
           jsonb_build_object('sale_id', u.id, 'amount', u.grand_total, 'threshold', cfg.refund_amount) as details
      from unlinked u, cfg
     where u.grand_total > cfg.refund_amount
    union all
    select 'UNLINKED_REFUND_FREQUENCY', 'high', p_shift_id,
           jsonb_build_object('max_in_one_hour', max(w.n), 'threshold', max(cfg.refunds_per_hour))
      from (select (select count(*) from unlinked u2
                     where u2.occurred_at >= u1.occurred_at
                       and u2.occurred_at < u1.occurred_at + interval '1 hour') as n
              from unlinked u1) w, cfg
    having max(w.n) > max(cfg.refunds_per_hour)
    union all
    select 'VOID_AMOUNT', 'medium', p_shift_id,
           jsonb_build_object('voided_amount', v.total, 'threshold', cfg.void_amount)
      from (select coalesce((select sum(s.grand_total) from app.sales s
                              where s.shift_id = p_shift_id and s.status = 'voided'), 0)
                 + coalesce((select sum(l.line_total) from app.sale_lines l join app.sales s on s.id = l.sale_id
                              where s.shift_id = p_shift_id and s.status <> 'voided' and l.voided_at is not null), 0)
                   as total) v, cfg
     where v.total > cfg.void_amount
    union all
    select 'POST_CLOSE_VOID', 'high', s.id, jsonb_build_object('sale_id', s.id, 'amount', s.grand_total)
      from app.sales s
     where s.shift_id = p_shift_id and s.status = 'voided'
       and exists (select 1 from app.sale_payments p where p.sale_id = s.id and p.method = 'cash')
    union all
    select 'MANUAL_DRAWER_OPENS', 'medium', p_shift_id,
           jsonb_build_object('manual_opens', d.n, 'threshold', cfg.drawer_opens)
      from (select count(*) as n from app.audit_log a
             where a.shift_id = p_shift_id and a.event_type = 'DRAWER_OPEN'
               and a.payload_json ->> 'reason' = 'manual') d, cfg
     where d.n > cfg.drawer_opens
  )
  insert into app.fraud_flags (tenant_id, branch_id, shift_id, staff_id, rule, severity, subject_id, details)
  select shift.tenant_id, shift.branch_id, shift.id, shift.staff_id, c.rule, c.severity, c.subject_id, c.details
    from candidates c, shift
  on conflict (rule, subject_id) do nothing
  returning *
$$;

alter table app.loss_prevention_settings enable row level security;
alter table app.fraud_flags enable row level security;

-- Thresholds are tenant-wide, so changing them needs tenant-wide FRAUD_REVIEW: a cashier must
-- not be able to switch off the rules that watch its own till.
create policy loss_prevention_settings_read on app.loss_prevention_settings for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.is_internal()));
create policy loss_prevention_settings_insert on app.loss_prevention_settings for insert
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('FRAUD_REVIEW')));
create policy loss_prevention_settings_update on app.loss_prevention_settings for update
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('FRAUD_REVIEW')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('FRAUD_REVIEW')));
create policy loss_prevention_settings_delete on app.loss_prevention_settings for delete
  using (tenant_id = (select app.current_tenant_id()) and (select app.has_permission('FRAUD_REVIEW')));

create policy fraud_flags_branch on app.fraud_flags for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

grant select, insert, update on app.loss_prevention_settings to market_backend;
grant select, insert on app.fraud_flags to market_backend;
grant update (status, reviewed_by, reviewed_at, review_note) on app.fraud_flags to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
