-- Egyptian Tax Authority B2C e-receipts (T7, spec §5.7). Each till keeps an unbroken
-- chain: every receipt names the previous receipt's UUID on the same device, so a
-- receipt cannot be deleted, back-dated or forked without the gap showing.

create table app.eta_submissions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null,
  branch_id           uuid not null,
  device_id           uuid not null,
  eta_submission_uuid text,
  receipt_count       int not null check (receipt_count between 1 and 500),
  payload_bytes       int not null check (payload_bytes between 1 and 1572864),
  status              text not null default 'pending'
                      check (status in ('pending', 'accepted', 'partially_accepted', 'rejected', 'failed')),
  response            jsonb,
  submitted_at        timestamptz,
  created_at          timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (device_id, branch_id) references app.pos_devices (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id)
);
comment on table app.eta_submissions is 'One ETA batch upload: at most 500 receipts or 1.5 MB, sent within 24 hours of issue.';

create table app.eta_receipts (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  branch_id         uuid not null,
  device_id         uuid not null,
  sale_id           uuid not null unique,
  receipt_type      text not null check (receipt_type in ('sale', 'return')),
  receipt_number    text not null,
  uuid              text not null unique check (uuid ~ '^[0-9a-fA-F]{64}$'),
  previous_uuid     text check (previous_uuid ~ '^[0-9a-fA-F]{64}$'),
  reference_uuid    text check (reference_uuid ~ '^[0-9a-fA-F]{64}$'),
  buyer_type        char(1) not null default 'P' check (buyer_type in ('B', 'P', 'F')),
  buyer_id          text,
  buyer_name        text,
  total_amount      numeric(14,2) not null check (total_amount >= 0),
  tax_total         numeric(14,2) not null default 0 check (tax_total >= 0),
  issued_at         timestamptz not null,
  document          jsonb not null check (jsonb_typeof(document) = 'object'),
  status            text not null default 'new' check (status in ('new', 'submitted', 'valid', 'invalid', 'cancelled')),
  submission_id     uuid,
  validation_errors jsonb,
  submitted_at      timestamptz,
  validated_at      timestamptz,
  created_at        timestamptz not null default now(),
  unique (device_id, receipt_number),
  unique (device_id, previous_uuid),
  check (buyer_type <> 'B' or buyer_id is not null),
  check (buyer_type <> 'P' or total_amount < 150000 or buyer_id is not null),
  check ((receipt_type = 'return') = (reference_uuid is not null)),
  foreign key (tenant_id, sale_id) references app.sales (tenant_id, id),
  foreign key (device_id, branch_id) references app.pos_devices (id, branch_id),
  foreign key (tenant_id, branch_id) references app.branches (tenant_id, id),
  foreign key (tenant_id, submission_id) references app.eta_submissions (tenant_id, id)
);
comment on column app.eta_receipts.uuid is 'The 64-hex SHA-256 receipt UUID computed by the till per the ETA spec (it includes previous_uuid).';
comment on column app.eta_receipts.status is 'new = ETA status 0, saved locally and not yet submitted.';
comment on column app.eta_receipts.document is 'The ETA receipt JSON exactly as serialised for submission.';
create unique index eta_receipts_genesis_key on app.eta_receipts (device_id) where previous_uuid is null;
create index eta_receipts_pending_idx on app.eta_receipts (tenant_id, issued_at) where status = 'new';

create function app.validate_eta_receipt() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale            record;
  v_original_issued timestamptz;
begin
  select s.sale_type, s.grand_total, s.tax_total, s.device_id into v_sale
    from app.sales s
   where s.id = new.sale_id and s.tenant_id = new.tenant_id;
  if not found then
    raise exception 'sale % does not exist in this tenant', new.sale_id;
  end if;
  if v_sale.sale_type <> new.receipt_type then
    raise exception 'a % receipt cannot describe a %', new.receipt_type, v_sale.sale_type;
  end if;
  if v_sale.grand_total <> new.total_amount or v_sale.tax_total <> new.tax_total then
    raise exception 'receipt totals must equal the totals of sale %', new.sale_id;
  end if;
  if v_sale.device_id is not null and v_sale.device_id <> new.device_id then
    raise exception 'sale % was rung up on another till', new.sale_id;
  end if;

  if new.previous_uuid is not null
     and not exists (select 1 from app.eta_receipts r
                      where r.uuid = new.previous_uuid and r.device_id = new.device_id) then
    raise exception 'previous receipt % is not on this till''s chain', new.previous_uuid;
  end if;

  if new.reference_uuid is not null then
    select r.issued_at into v_original_issued
      from app.eta_receipts r
     where r.uuid = new.reference_uuid and r.tenant_id = new.tenant_id and r.receipt_type = 'sale';
    if not found then
      raise exception 'original receipt % does not exist in this tenant', new.reference_uuid;
    end if;
    if new.issued_at > v_original_issued + interval '540 days' then
      raise exception 'returns are accepted for 540 days after the sale';
    end if;
  end if;

  return new;
end
$$;

create function app.guard_eta_receipt_update() returns trigger
language plpgsql
as $$
begin
  if (new.id, new.tenant_id, new.branch_id, new.device_id, new.sale_id, new.receipt_type, new.receipt_number,
      new.uuid, new.previous_uuid, new.reference_uuid, new.buyer_type, new.buyer_id, new.buyer_name,
      new.total_amount, new.tax_total, new.issued_at, new.document, new.created_at)
     is distinct from
     (old.id, old.tenant_id, old.branch_id, old.device_id, old.sale_id, old.receipt_type, old.receipt_number,
      old.uuid, old.previous_uuid, old.reference_uuid, old.buyer_type, old.buyer_id, old.buyer_name,
      old.total_amount, old.tax_total, old.issued_at, old.document, old.created_at) then
    raise exception 'issued receipts cannot change; only their submission status can';
  end if;
  return new;
end
$$;

create trigger eta_receipts_validate before insert on app.eta_receipts
  for each row execute function app.validate_eta_receipt();
create trigger eta_receipts_guard before update on app.eta_receipts
  for each row execute function app.guard_eta_receipt_update();
create trigger eta_receipts_no_delete before delete on app.eta_receipts
  for each row execute function app.prevent_delete();

create view app.eta_overdue_receipts with (security_invoker = true) as
  select r.id, r.tenant_id, r.branch_id, r.device_id, r.receipt_number, r.uuid, r.issued_at,
         now() - r.issued_at as age
    from app.eta_receipts r
   where r.status = 'new' and r.issued_at < now() - interval '24 hours';

alter table app.eta_submissions enable row level security;
alter table app.eta_receipts enable row level security;

create policy eta_submissions_branch on app.eta_submissions for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));

create policy eta_receipts_branch on app.eta_receipts for all
  using (tenant_id = (select app.current_tenant_id())
         and branch_id = any ((select app.accessible_branch_ids())::uuid[]))
  with check (tenant_id = (select app.current_tenant_id())
              and branch_id = any ((select app.accessible_branch_ids())::uuid[]));
create policy eta_receipts_customer_read on app.eta_receipts for select
  using ((select app.current_customer_id()) is not null
         and exists (select 1 from app.sales s
                      where s.id = sale_id and s.customer_id = (select app.current_customer_id())));

grant select, insert on app.eta_submissions, app.eta_receipts to market_backend;
grant update (status, response, submitted_at, eta_submission_uuid) on app.eta_submissions to market_backend;
grant update (status, submission_id, validation_errors, submitted_at, validated_at) on app.eta_receipts to market_backend;
grant select on app.eta_overdue_receipts to market_backend;

revoke execute on all functions in schema app from public;
grant execute on all functions in schema app to market_backend;
