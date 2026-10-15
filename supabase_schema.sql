-- 我的單字冒險島：雲端好友版資料庫（Supabase SQL Editor 執行一次）
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default '小小冒險家' check (char_length(nickname) between 1 and 24),
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 8)),
  xp bigint not null default 0 check (xp >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
create index if not exists friendships_friend_id_idx on public.friendships(friend_id);

create table if not exists public.user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.xp_events (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  points integer not null check (points in (10, 12, 15)),
  created_at timestamptz not null default now()
);
create index if not exists xp_events_user_day_idx on public.xp_events(user_id, created_at);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.user_data enable row level security;
alter table public.xp_events enable row level security;

-- Explicit grants paired with RLS policies.
grant select, insert on public.profiles to authenticated;
grant select on public.friendships to authenticated;
grant select, insert, update on public.user_data to authenticated;

drop policy if exists "Read self and friends profiles" on public.profiles;
create policy "Read self and friends profiles" on public.profiles for select to authenticated
using (id = auth.uid() or exists (select 1 from public.friendships f where f.user_id = auth.uid() and f.friend_id = profiles.id));
drop policy if exists "Insert own profile" on public.profiles;
create policy "Insert own profile" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "Update own profile nickname only" on public.profiles;
create policy "Update own profile nickname only" on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());
-- Prevent direct client updates to XP and invite codes. Only safe RPCs may change XP or friends.
revoke update on public.profiles from authenticated;
grant update (nickname) on public.profiles to authenticated;

drop policy if exists "Read own friendships" on public.friendships;
create policy "Read own friendships" on public.friendships for select to authenticated using (user_id = auth.uid());
drop policy if exists "Read own cloud data" on public.user_data;
create policy "Read own cloud data" on public.user_data for select to authenticated using (user_id = auth.uid());
drop policy if exists "Insert own cloud data" on public.user_data;
create policy "Insert own cloud data" on public.user_data for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Update own cloud data" on public.user_data;
create policy "Update own cloud data" on public.user_data for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
-- XP event rows are private and may only be written through the RPC.
revoke all on public.xp_events from anon, authenticated;
revoke insert, update, delete on public.friendships from anon, authenticated;

create or replace function public.add_friend_by_code(p_invite_code text)
returns text language plpgsql security definer set search_path = public
as $$
declare target_id uuid;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select id into target_id from public.profiles where invite_code = upper(trim(p_invite_code));
  if target_id is null then raise exception '找不到這個邀請碼'; end if;
  if target_id = auth.uid() then raise exception '不能新增自己為好友'; end if;
  insert into public.friendships(user_id, friend_id) values (auth.uid(), target_id) on conflict do nothing;
  insert into public.friendships(user_id, friend_id) values (target_id, auth.uid()) on conflict do nothing;
  return '好友已加入！';
end; $$;
revoke all on function public.add_friend_by_code(text) from public;
grant execute on function public.add_friend_by_code(text) to authenticated;

create or replace function public.remove_friend(p_friend_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  delete from public.friendships where (user_id = auth.uid() and friend_id = p_friend_id)
     or (user_id = p_friend_id and friend_id = auth.uid());
  return true;
end; $$;
revoke all on function public.remove_friend(uuid) from public;
grant execute on function public.remove_friend(uuid) to authenticated;

create or replace function public.award_xp(p_points integer, p_event_id uuid)
returns bigint language plpgsql security definer set search_path = public
as $$
declare current_xp bigint; daily_total integer;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_points not in (10, 12, 15) then raise exception '無效的 XP 獎勵'; end if;
  -- Idempotency: repeated event IDs cannot grant XP twice.
  insert into public.xp_events(id, user_id, points) values (p_event_id, auth.uid(), p_points) on conflict (id) do nothing;
  if not found then select xp into current_xp from public.profiles where id = auth.uid(); return current_xp; end if;
  select coalesce(sum(points), 0) into daily_total from public.xp_events
    where user_id = auth.uid() and created_at >= date_trunc('day', now());
  if daily_total > 300 then
    delete from public.xp_events where id = p_event_id and user_id = auth.uid();
    raise exception '今日 XP 獎勵已達上限，明天再來冒險！';
  end if;
  update public.profiles set xp = xp + p_points where id = auth.uid() returning xp into current_xp;
  return current_xp;
end; $$;
revoke all on function public.award_xp(integer, uuid) from public;
grant execute on function public.award_xp(integer, uuid) to authenticated;

-- Create a profile automatically for new Auth users. Invite code is generated server-side.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, nickname)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'nickname', '小小冒險家'), 24))
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Realtime is optional; the app can refresh the leaderboard manually without it.
