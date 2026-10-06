-- Safety triggers: database-level guarantees for the moderation pipeline.
--
-- Column grants already stop clients writing moderation columns. These
-- triggers add the rules grants can't express:
--   * anything a client creates starts as 'pending'
--   * any client change to content sends it back to 'pending'
--   * item types are gated by trust level (brief 5.4.3)
-- The server (service_role, or postgres in scheduled jobs) is exempt: it is
-- what moderates.
--
-- The guard functions are deliberately SECURITY INVOKER: they detect clients
-- with current_user, which inside a security definer function would always
-- be the function owner.

create function private.is_client_role()
returns boolean
language sql
stable
set search_path = ''
as $$
  select current_user in ('anon', 'authenticated');
$$;

-- Minimum trust level needed to post each item type.
-- Level 0: text, drawing, image, link, code. Everything else needs level 1.
create function private.min_trust_for_item_type(item_type public.plot_item_type)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when item_type in ('text', 'drawing', 'image', 'link', 'code') then 0::smallint
    else 1::smallint
  end;
$$;

-- Records owner activity on a plot (slows decay, brief 5.2). Security definer
-- because clients cannot update plots; only reachable from triggers since
-- the private schema is not exposed, and it only touches the caller's plot.
create function private.bump_plot_activity(target_plot_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.plots
    set last_active_at = now()
    where id = target_plot_id and owner_id = (select auth.uid());
$$;

grant execute on function private.is_client_role() to anon, authenticated, service_role;
grant execute on function private.min_trust_for_item_type(public.plot_item_type)
  to anon, authenticated, service_role;
grant execute on function private.bump_plot_activity(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- plot_items
-- ---------------------------------------------------------------------------

create function private.plot_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  owner_trust smallint;
begin
  if not private.is_client_role() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select u.trust_level into owner_trust
    from public.plots p
    join public.users u on u.id = p.owner_id
    where p.id = new.plot_id;

    if owner_trust is null or owner_trust < private.min_trust_for_item_type(new.type) then
      raise exception 'Your trust level does not allow % items yet', new.type
        using errcode = 'insufficient_privilege';
    end if;

    new.moderation_status := 'pending';
    new.moderation_reason := null;
    new.moderated_at := null;
    return new;
  end if;

  -- UPDATE: identity columns are fixed (column grants also enforce this).
  new.id := old.id;
  new.plot_id := old.plot_id;
  new.type := old.type;
  new.created_at := old.created_at;

  if new.content is distinct from old.content then
    new.moderation_status := 'pending';
    new.moderation_reason := null;
    new.moderated_at := null;
  else
    new.moderation_status := old.moderation_status;
    new.moderation_reason := old.moderation_reason;
    new.moderated_at := old.moderated_at;
  end if;

  return new;
end;
$$;

create trigger plot_items_guard
  before insert or update on public.plot_items
  for each row execute function private.plot_items_guard();

create function private.plot_items_touch_activity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_client_role() then
    perform private.bump_plot_activity(coalesce(new.plot_id, old.plot_id));
  end if;
  return null;
end;
$$;

create trigger plot_items_touch_activity
  after insert or update or delete on public.plot_items
  for each row execute function private.plot_items_touch_activity();

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------

create function private.comments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.is_client_role() then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.plot_id := old.plot_id;
    new.author_id := old.author_id;
    new.created_at := old.created_at;
    if new.body is not distinct from old.body then
      new.moderation_status := old.moderation_status;
      new.moderation_reason := old.moderation_reason;
      new.moderated_at := old.moderated_at;
      return new;
    end if;
  end if;

  new.moderation_status := 'pending';
  new.moderation_reason := null;
  new.moderated_at := null;
  return new;
end;
$$;

create trigger comments_guard
  before insert or update on public.comments
  for each row execute function private.comments_guard();

-- ---------------------------------------------------------------------------
-- reports: clients can only open reports.
-- ---------------------------------------------------------------------------

create function private.reports_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_client_role() then
    new.status := 'open';
    new.resolved_by := null;
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

create trigger reports_guard
  before insert on public.reports
  for each row execute function private.reports_guard();

-- Trigger functions run with the table's trigger machinery; they need no
-- direct EXECUTE grant for that, so none is given.
