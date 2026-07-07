-- ============================================================
--  ServiceTag — Supabase schema (Postgres)
--  Run this in: Supabase Dashboard → SQL Editor → New query → Run
--  It is safe to re-run: it drops and recreates cleanly.
-- ============================================================

-- Optional clean slate (comment out if you have real data)
drop table if exists public.unit_events cascade;
drop table if exists public.units cascade;
drop table if exists public.locations cascade;

-- ------------------------------------------------------------
-- 1. LOCATIONS — your custom-named bins, benches, shelves
-- ------------------------------------------------------------
create table public.locations (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. UNITS — one row per physical, serialized item
--    grade / disposition use CHECK constraints (not enums) so
--    you can change your depot vocabulary later with one ALTER.
-- ------------------------------------------------------------
create table public.units (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  sn           text not null,
  sku          text default '',
  description  text default '',
  grade        text default 'none'
                 check (grade in ('none','A','B','C','D','scrap')),
  disposition  text not null default 'needs-inspection'
                 check (disposition in ('needs-inspection','stock','refurb','scrap','shipped')),
  location_id  uuid references public.locations(id) on delete set null,  -- null = Unassigned
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (user_id, sn)   -- a user can't have two units with the same serial
);

-- ------------------------------------------------------------
-- 3. UNIT_EVENTS — the append-only condition history.
--    This table is the product. Never UPDATE or DELETE rows
--    here in normal use; you only INSERT. The unit's current
--    grade/disposition/location are denormalized onto `units`
--    for fast lists, but the truth is the event log.
-- ------------------------------------------------------------
create table public.unit_events (
  id           uuid primary key default gen_random_uuid(),
  unit_id      uuid not null references public.units(id) on delete cascade,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  event_type   text not null
                 check (event_type in ('received','inspected','graded','moved','note','shipped')),
  note         text default '',
  grade        text check (grade in ('A','B','C','D','scrap')),
  disposition  text check (disposition in ('needs-inspection','stock','refurb','scrap','shipped')),
  location_id  uuid references public.locations(id) on delete set null,
  created_by   text default 'You',
  created_at   timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Indexes for the queries the app actually runs
-- ------------------------------------------------------------
create index units_user_idx        on public.units (user_id);
create index units_location_idx    on public.units (location_id);
create index events_unit_idx       on public.unit_events (unit_id);
create index events_user_time_idx  on public.unit_events (user_id, created_at desc);

-- ------------------------------------------------------------
-- Keep units.updated_at fresh on every change
-- ------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger units_touch_updated
  before update on public.units
  for each row execute function public.touch_updated_at();

-- ============================================================
-- 4. ROW LEVEL SECURITY
--    Without this, the public anon key could read everyone's
--    data. With it, every query is silently scoped to the
--    signed-in user. This is the security backbone — do not skip.
-- ============================================================
alter table public.locations   enable row level security;
alter table public.units       enable row level security;
alter table public.unit_events enable row level security;

create policy "own locations" on public.locations
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "own units" on public.units
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "own events" on public.unit_events
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Done. Tables, constraints, indexes, triggers, and RLS are live.
