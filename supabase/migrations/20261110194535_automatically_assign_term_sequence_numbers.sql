-- Automatically assign term sequence numbers within each academic year.
-- Canonical ordering: Fall=1, Spring=2, Summer=3.
-- Other term kinds receive the next available number.
begin;
set local lock_timeout = '5s';

create or replace function private.assign_term_sequence_number()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_next_sequence integer;
begin
  -- Unlinked terms are not part of an academic-year sequence.
  if new.academic_year_id is null then
    new.sequence_number := null;
    return new;
  end if;

  -- Serialize sequence allocation for this academic year.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.academic_year_id::text, 0)
  );

  case new.term_kind
    when 'fall'::public.academic_term_kind then
      new.sequence_number := 1;
    when 'spring'::public.academic_term_kind then
      new.sequence_number := 2;
    when 'summer'::public.academic_term_kind then
      new.sequence_number := 3;
    else
      select coalesce(max(t.sequence_number), 0) + 1
        into v_next_sequence
      from public.terms t
      where t.academic_year_id = new.academic_year_id
        and t.tenant_id = new.tenant_id
        and t.id is distinct from new.id;

      new.sequence_number := v_next_sequence;
  end case;

  return new;
end;
$function$;

revoke all on function private.assign_term_sequence_number() from public;
grant execute on function private.assign_term_sequence_number() to authenticated, service_role;

drop trigger if exists terms_assign_sequence_number on public.terms;
create trigger terms_assign_sequence_number
before insert or update of academic_year_id, term_kind
on public.terms
for each row
execute function private.assign_term_sequence_number();

commit;