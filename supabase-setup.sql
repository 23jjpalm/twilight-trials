-- Twilight Trials · run once in Supabase SQL Editor in a NEW project.
-- No default categories/runs/users. Requires Supabase Auth with Email provider enabled.
create extension if not exists pgcrypto;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text not null check (username ~ '^[A-Za-z0-9_]{3,24}$'),
 role text not null default 'runner' check (role in ('runner','moderator','admin')),
 banned boolean not null default false,
 created_at timestamptz not null default now()
);
create unique index profiles_username_ci on public.profiles(lower(username));

create table public.categories (
 id uuid primary key default gen_random_uuid(),
 game text not null check (game in ('tphd','tp')),
 name text not null check (char_length(name) between 3 and 48),
 icon text not null default '✧',
 label text not null check (char_length(label) between 1 and 65),
 description text not null check (char_length(description) between 1 and 350),
 rules text not null check (char_length(rules) between 1 and 1500),
 difficulty text not null default 'COMMUNITY',
 color text not null default 'teal',
 status text not null default 'active' check (status in ('active','archived')),
 creator uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
create table public.proposals (
 id uuid primary key default gen_random_uuid(),
 proposer uuid not null references public.profiles(id),
 game text not null check (game in ('tphd','tp')),
 name text not null check (char_length(name) between 3 and 48),
 label text not null check (char_length(label) between 1 and 65),
 description text not null check (char_length(description) between 1 and 350),
 rules text not null check (char_length(rules) between 1 and 1500),
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 created_at timestamptz not null default now()
);
create table public.runs (
 id uuid primary key default gen_random_uuid(),
 category_id uuid not null references public.categories(id),
 user_id uuid not null references public.profiles(id),
 time_text text not null check (time_text ~ '^[0-9]{1,4}:[0-5][0-9]:[0-5][0-9]\.[0-9]{3}$'),
 milliseconds bigint not null check (milliseconds > 0),
 run_date date not null check (run_date <= current_date),
 proof_url text not null check (char_length(proof_url) between 12 and 600 and proof_url ~ '^https://'),
 status text not null default 'pending' check (status in ('pending','verified','rejected')),
 note text not null default '',
 reviewer uuid references public.profiles(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index runs_category_rank on public.runs(category_id,status,milliseconds);
create index runs_pending on public.runs(status,created_at);

-- Create an immutable identity when Supabase Auth registers the user.
create or replace function public.create_runner_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,username) values(new.id, new.raw_user_meta_data->>'username');
 return new;
end; $$;
create trigger create_runner_profile_after_signup after insert on auth.users
for each row execute function public.create_runner_profile();

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and role in ('admin','moderator') and not banned)
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and not banned)
$$;
create or replace function public.is_active_runner() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and not banned)
$$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.proposals enable row level security;
alter table public.runs enable row level security;

-- A username is public information on a leaderboard. Email/password remain in auth.users and aren't exposed.
create policy "Read public profiles" on public.profiles for select to anon,authenticated using (true);
create policy "Read active categories or staff archives" on public.categories for select to anon,authenticated using (status='active' or public.is_staff());
create policy "Staff create categories" on public.categories for insert to authenticated with check (public.is_staff() and creator=(select auth.uid()));
create policy "Staff edit categories" on public.categories for update to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "Proposers and staff read proposals" on public.proposals for select to authenticated using (proposer=(select auth.uid()) or public.is_staff());
create policy "Runners suggest categories" on public.proposals for insert to authenticated with check (proposer=(select auth.uid()) and public.is_active_runner() and status='pending');
create policy "Public verified, owner private, staff all" on public.runs for select to anon,authenticated using (status='verified' or user_id=(select auth.uid()) or public.is_staff());
create policy "Runners submit pending only" on public.runs for insert to authenticated
with check (user_id=(select auth.uid()) and public.is_active_runner() and status='pending'
 and reviewer is null and reviewed_at is null and note='' and exists(select 1 from public.categories c where c.id=category_id and c.status='active'));

-- Functions own all privileged actions; browsers cannot simply update profiles or run status.
create or replace function public.review_run(p_run uuid,p_action text,p_note text default '') returns void
language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 if p_action not in ('verified','rejected') then raise exception 'Invalid decision'; end if;
 if char_length(coalesce(p_note,''))>500 then raise exception 'Note too long'; end if;
 update public.runs set status=p_action,note=coalesce(p_note,''),reviewer=auth.uid(),reviewed_at=now()
 where id=p_run and status='pending';
 if not found then raise exception 'Run is not pending'; end if;
end; $$;
create or replace function public.review_proposal(p_proposal uuid,p_action text) returns void
language plpgsql security definer set search_path = '' as $$
declare item public.proposals%rowtype;
begin
 if not public.is_staff() then raise exception 'Not authorized'; end if;
 if p_action not in ('approve','reject') then raise exception 'Invalid decision'; end if;
 select * into item from public.proposals where id=p_proposal and status='pending' for update;
 if not found then raise exception 'Proposal is not pending'; end if;
 if p_action='approve' then
 insert into public.categories(game,name,label,description,rules,creator)
 values(item.game,item.name,item.label,item.description,item.rules,auth.uid());
 end if;
 update public.proposals set status=case when p_action='approve' then 'approved' else 'rejected' end where id=p_proposal;
end; $$;
create or replace function public.manage_user(p_user uuid,p_action text) returns void
language plpgsql security definer set search_path = '' as $$
declare target_role text;
begin
 if not public.is_admin() then raise exception 'Admin permission required'; end if;
 if p_user=auth.uid() then raise exception 'Cannot modify your own account'; end if;
 select role into target_role from public.profiles where id=p_user for update;
 if not found then raise exception 'No such user'; end if;
 if target_role='admin' then raise exception 'Cannot modify another admin'; end if;
 if p_action='ban' then update public.profiles set banned=true where id=p_user;
 elsif p_action='unban' then update public.profiles set banned=false where id=p_user;
 elsif p_action='moderator' then update public.profiles set role='moderator' where id=p_user;
 elsif p_action='runner' then update public.profiles set role='runner' where id=p_user;
 else raise exception 'Invalid action'; end if;
end; $$;

-- Explicit grants protect against permissive default privileges.
revoke all on public.profiles, public.categories, public.proposals, public.runs from anon,authenticated;
grant select on public.profiles to anon,authenticated;
grant select on public.categories to anon,authenticated;
grant insert,update on public.categories to authenticated;
grant select,insert on public.proposals to authenticated;
grant select on public.runs to anon,authenticated;
grant insert (category_id,user_id,time_text,milliseconds,run_date,proof_url) on public.runs to authenticated;
revoke all on function public.is_staff(),public.is_admin(),public.is_active_runner() from public;
grant execute on function public.is_staff(),public.is_admin(),public.is_active_runner() to anon,authenticated;
revoke all on function public.review_run(uuid,text,text),public.review_proposal(uuid,text),public.manage_user(uuid,text) from public;
grant execute on function public.review_run(uuid,text,text),public.review_proposal(uuid,text),public.manage_user(uuid,text) to authenticated;

-- AFTER you register an account, run this line in SQL Editor with YOUR actual username:
-- update public.profiles set role='admin' where lower(username)=lower('YOUR_USERNAME');
-- Never expose a Supabase service_role/secret key in GitHub or config.js.
