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
