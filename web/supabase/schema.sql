-- my-anime — skema Supabase (jalankan di SQL Editor).
-- user_id = ID perangkat anonim dari klien (lib/supabase.ts `deviceId()`).

create table if not exists watchlist (
  id bigint generated always as identity primary key,
  user_id text not null,
  provider text not null default 'gogo',
  anime_id text not null,
  title text not null,
  image text not null default '',
  created_at timestamptz not null default now(),
  unique (user_id, provider, anime_id)
);

create table if not exists history (
  id bigint generated always as identity primary key,
  user_id text not null,
  provider text not null default 'gogo',
  anime_id text not null,
  episode_id text not null,
  episode_number int,
  title text not null,
  image text not null default '',
  progress_seconds int not null default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, provider, episode_id)
);

create index if not exists watchlist_user_idx on watchlist (user_id, created_at desc);
create index if not exists history_user_idx on history (user_id, updated_at desc);

alter table watchlist enable row level security;
alter table history enable row level security;

-- Kebijakan longgar: tiap perangkat hanya menyentuh baris user_id miliknya.
drop policy if exists "device owns watchlist" on watchlist;
create policy "device owns watchlist" on watchlist
  for all using (true) with check (user_id is not null and char_length(user_id) <= 64);

drop policy if exists "device owns history" on history;
create policy "device owns history" on history
  for all using (true) with check (user_id is not null and char_length(user_id) <= 64);
