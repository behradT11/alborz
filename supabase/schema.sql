-- =====================================================================
-- مسیر طلا — اسکیمای کامل Supabase (PostgreSQL)
-- این فایل را یک‌جا در SQL Editor پروژهٔ Supabase اجرا کنید.
-- اجرای دوباره امن است (idempotent): جدول‌ها و سیاست‌ها اگر وجود داشته باشند بازسازی نمی‌شوند.
-- اصل امنیتی: هر جدول کاربری RLS دارد و فقط ردیف‌های user_id = auth.uid() قابل خواندن/نوشتن است.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- ۱) ادمین‌ها (فقط از طریق SQL Editor قابل افزودن؛ هیچ سیاست نوشتنی ندارد)
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
-- کاربر فقط می‌تواند ببیند خودش ادمین است یا نه
drop policy if exists admins_self_read on public.admins;
create policy admins_self_read on public.admins for select to authenticated
  using (user_id = auth.uid());

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------
-- ۲) پروفایل
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 40),
  grade smallint check (grade between 9 and 12),
  target_stage smallint not null default 1 check (target_stage between 1 and 3),
  exam_dates jsonb not null default '{}'::jsonb,
  daily_minutes jsonb not null default '{}'::jsonb,
  levels jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  onboarded boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists profiles_own on public.profiles;
create policy profiles_own on public.profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ساخت خودکار پروفایل هنگام ثبت‌نام
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'display_name', ''), 40))
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- تابع عمومی به‌روزرسانی updated_at
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- ۳) جدول‌های کاربری. همه: id uuid، user_id پیش‌فرض auth.uid()
-- ---------------------------------------------------------------------

-- پیشرفت: هر ردیف = یک گام (روخوانی، سرفصل‌نویسی، ...) از یک واحد (فصل)
create table if not exists public.progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  unit_id text not null check (char_length(unit_id) <= 80),
  step text not null check (step in ('read','outline','concept','video','test','review')),
  done_at timestamptz not null default now(),
  unique (user_id, unit_id, step)
);

-- جلسه‌های مطالعه (اتاق مطالعه)
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  minutes integer not null check (minutes between 1 and 600),
  unit_id text check (char_length(unit_id) <= 80),
  kind text not null default 'focus' check (kind in ('focus','review','exam','manual')),
  focus smallint check (focus between 1 and 5),
  note text check (char_length(note) <= 2000)
);
create index if not exists sessions_user_time on public.sessions(user_id, started_at desc);

-- یادداشت‌ها
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  unit_id text check (char_length(unit_id) <= 80),
  title text not null default '' check (char_length(title) <= 120),
  body text not null default '' check (char_length(body) <= 20000),
  updated_at timestamptz not null default now()
);

-- تنظیمات شخصی هر واحد (تخمین زمان شخصی، لینک فیلم، ...)
create table if not exists public.unit_prefs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  unit_id text not null check (char_length(unit_id) <= 80),
  minutes integer check (minutes between 10 and 6000),
  skip boolean not null default false,
  unique (user_id, unit_id)
);

-- لینک‌های شخصی کاربر برای هر منبع/واحد
create table if not exists public.user_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  unit_id text check (char_length(unit_id) <= 80),
  title text not null check (char_length(title) between 1 and 120),
  url text not null check (url ~* '^https?://' and char_length(url) <= 500),
  kind text not null default 'link' check (kind in ('link','video','test','book')),
  created_at timestamptz not null default now()
);

-- فایل‌های آپلودی (متادیتا؛ خود فایل در Storage)
create table if not exists public.files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  unit_id text check (char_length(unit_id) <= 80),
  name text not null check (char_length(name) <= 160),
  path text not null check (char_length(path) <= 300),
  size integer not null check (size between 1 and 20971520),
  mime text not null default '' check (char_length(mime) <= 100),
  created_at timestamptz not null default now()
);

-- سؤال‌های شخصی (بانک سؤال کاربر، مثلاً سؤال‌های سال‌های قبل که خودش وارد می‌کند)
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  subject text not null check (subject in ('econ','mgmt','gov','stat','soc')),
  stage smallint not null default 1 check (stage between 1 and 3),
  unit_id text check (char_length(unit_id) <= 80),
  text text not null check (char_length(text) between 3 and 3000),
  options jsonb not null,
  answer smallint not null check (answer between 0 and 5),
  explanation text not null default '' check (char_length(explanation) <= 3000),
  source text not null default '' check (char_length(source) <= 160),
  created_at timestamptz not null default now()
);

-- آزمون‌های شبیه‌ساز
create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  stage smallint not null check (stage between 1 and 3),
  config jsonb not null default '{}'::jsonb,
  items jsonb not null default '[]'::jsonb,
  correct integer not null default 0,
  wrong integer not null default 0,
  blank integer not null default 0,
  percent numeric(6,2) not null default 0,
  duration_sec integer not null default 0,
  created_at timestamptz not null default now()
);

-- دفتر اشتباهات
create table if not exists public.mistakes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  unit_id text check (char_length(unit_id) <= 80),
  subject text check (subject in ('econ','mgmt','gov','stat','soc')),
  prompt text not null check (char_length(prompt) between 1 and 3000),
  my_answer text not null default '' check (char_length(my_answer) <= 1000),
  right_answer text not null default '' check (char_length(right_answer) <= 1000),
  reason text not null check (reason in ('concept','careless','time','trap','memory','calc','unknown')),
  lesson text not null default '' check (char_length(lesson) <= 2000),
  srs jsonb not null default '{}'::jsonb,
  resolved boolean not null default false,
  created_at timestamptz not null default now()
);

-- فلش‌کارت‌ها
create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  deck text not null default 'شخصی' check (char_length(deck) <= 40),
  front text not null check (char_length(front) between 1 and 1000),
  back text not null check (char_length(back) between 1 and 3000),
  ref text check (char_length(ref) <= 80),
  srs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- هدف‌گذاری و مرور هفتگی
create table if not exists public.weeks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  week_start date not null,
  goals jsonb not null default '[]'::jsonb,
  reflection jsonb not null default '{}'::jsonb,
  unique (user_id, week_start)
);

-- چک‌این روزانهٔ انرژی (مدیریت خستگی)
create table if not exists public.checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day date not null,
  energy smallint not null check (energy between 1 and 5),
  sleep numeric(3,1) check (sleep between 0 and 16),
  stress smallint check (stress between 1 and 5),
  unique (user_id, day)
);

-- کارگاه فاینمن و کارگاه تحلیل سیاستی
create table if not exists public.workshops (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('feynman','policy')),
  unit_id text check (char_length(unit_id) <= 80),
  title text not null check (char_length(title) between 1 and 160),
  content jsonb not null default '{}'::jsonb,
  score smallint check (score between 0 and 100),
  updated_at timestamptz not null default now()
);

-- RLS یکسان برای همهٔ جدول‌های کاربری
do $$
declare t text;
begin
  foreach t in array array['progress','sessions','notes','unit_prefs','user_links','files',
                           'questions','attempts','mistakes','cards','weeks','checkins','workshops']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for all to authenticated
                    using (user_id = auth.uid()) with check (user_id = auth.uid())', t || '_own', t);
    execute format('create index if not exists %I on public.%I(user_id)', t || '_user_idx', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- ۴) کاتالوگ منابع (مدیریت از پنل ادمین؛ خواندن برای همه)
-- ---------------------------------------------------------------------
create table if not exists public.catalog (
  id text primary key default 'main',
  version integer not null default 1,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.catalog enable row level security;
drop policy if exists catalog_read on public.catalog;
create policy catalog_read on public.catalog for select to anon, authenticated using (true);
drop policy if exists catalog_admin_write on public.catalog;
create policy catalog_admin_write on public.catalog for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- بانک سؤال عمومی (ادمین اضافه می‌کند؛ همهٔ کاربران واردشده می‌خوانند)
create table if not exists public.public_questions (
  id uuid primary key default gen_random_uuid(),
  subject text not null check (subject in ('econ','mgmt','gov','stat','soc')),
  stage smallint not null default 1 check (stage between 1 and 3),
  unit_id text check (char_length(unit_id) <= 80),
  text text not null check (char_length(text) between 3 and 3000),
  options jsonb not null,
  answer smallint not null check (answer between 0 and 5),
  explanation text not null default '' check (char_length(explanation) <= 3000),
  source text not null default '' check (char_length(source) <= 160),
  created_at timestamptz not null default now()
);
alter table public.public_questions enable row level security;
drop policy if exists pq_read on public.public_questions;
create policy pq_read on public.public_questions for select to authenticated using (true);
drop policy if exists pq_admin on public.public_questions;
create policy pq_admin on public.public_questions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- ۵) گروه مطالعه (اختیاری، با رضایت صریح)
-- اعضا فقط نام نمایشی و دقیقه‌های هفتهٔ جاری یکدیگر را از طریق تابع امن می‌بینند.
-- ---------------------------------------------------------------------
create table if not exists public.study_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 40),
  code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  owner uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.group_members (
  group_id uuid not null references public.study_groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  share_stats boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
alter table public.study_groups enable row level security;
alter table public.group_members enable row level security;

create or replace function public.is_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.group_members where group_id = g and user_id = auth.uid());
$$;
revoke all on function public.is_member(uuid) from public;
grant execute on function public.is_member(uuid) to authenticated;

drop policy if exists sg_read on public.study_groups;
create policy sg_read on public.study_groups for select to authenticated
  using (owner = auth.uid() or public.is_member(id));
drop policy if exists sg_insert on public.study_groups;
create policy sg_insert on public.study_groups for insert to authenticated
  with check (owner = auth.uid());
drop policy if exists sg_owner_delete on public.study_groups;
create policy sg_owner_delete on public.study_groups for delete to authenticated
  using (owner = auth.uid());

drop policy if exists gm_self on public.group_members;
create policy gm_self on public.group_members for select to authenticated
  using (user_id = auth.uid());
drop policy if exists gm_self_update on public.group_members;
create policy gm_self_update on public.group_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists gm_self_delete on public.group_members;
create policy gm_self_delete on public.group_members for delete to authenticated
  using (user_id = auth.uid());
-- عضویت فقط از طریق تابع join_group (با کد) انجام می‌شود؛ insert مستقیم سیاست ندارد.

create or replace function public.create_group(p_name text) returns public.study_groups
language plpgsql security definer set search_path = public as $$
declare g public.study_groups;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if (select count(*) from public.study_groups where owner = auth.uid()) >= 5 then
    raise exception 'group limit reached';
  end if;
  insert into public.study_groups(name, owner) values (trim(p_name), auth.uid()) returning * into g;
  insert into public.group_members(group_id, user_id) values (g.id, auth.uid());
  return g;
end; $$;

create or replace function public.join_group(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare gid uuid; n int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select id into gid from public.study_groups where code = upper(trim(p_code));
  if gid is null then raise exception 'invalid code'; end if;
  select count(*) into n from public.group_members where group_id = gid;
  if n >= 30 then raise exception 'group full'; end if;
  insert into public.group_members(group_id, user_id) values (gid, auth.uid())
    on conflict do nothing;
  return gid;
end; $$;

-- لیدربورد دوستانه: فقط اعضای همان گروه، فقط کسانی که share_stats روشن است
create or replace function public.group_board(p_group uuid) returns table(display_name text, minutes bigint, is_me boolean)
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.display_name, ''), 'دوست بی‌نام') as display_name,
         coalesce(sum(s.minutes), 0) as minutes,
         m.user_id = auth.uid() as is_me
  from public.group_members m
  join public.profiles p on p.id = m.user_id
  left join public.sessions s on s.user_id = m.user_id
       and s.started_at >= date_trunc('week', now() + interval '2 day') - interval '2 day'
  where m.group_id = p_group
    and public.is_member(p_group)
    and (m.share_stats or m.user_id = auth.uid())
  group by p.display_name, m.user_id
  order by minutes desc;
$$;

revoke all on function public.create_group(text) from public;
revoke all on function public.join_group(text) from public;
revoke all on function public.group_board(uuid) from public;
grant execute on function public.create_group(text) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.group_board(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- ۶) حذف حساب توسط خود کاربر (همهٔ داده‌های جدول‌ها با cascade پاک می‌شود)
-- فایل‌های Storage را اپ پیش از فراخوانی این تابع از طریق Storage API پاک می‌کند،
-- چون Supabase حذف مستقیم از storage.objects با SQL را مسدود می‌کند.
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from auth.users where id = auth.uid();
end; $$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------
-- ۷) Storage: باکت خصوصی فایل‌ها؛ هر کاربر فقط پوشهٔ <uid>/ خودش
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('user-files', 'user-files', false, 20971520,
        array['application/pdf','image/png','image/jpeg','image/webp','text/plain',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists uf_read on storage.objects;
create policy uf_read on storage.objects for select to authenticated
  using (bucket_id = 'user-files' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists uf_insert on storage.objects;
create policy uf_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'user-files' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists uf_delete on storage.objects;
create policy uf_delete on storage.objects for delete to authenticated
  using (bucket_id = 'user-files' and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- پس از ثبت‌نام خودتان، برای ادمین شدن (یک بار) این را با ایمیل خودتان اجرا کنید:
--   insert into public.admins(user_id)
--   select id from auth.users where email = 'you@example.com';
-- =====================================================================
