# Explore + Share Setup (Beginner Guide, Free Tier)

This app now has:
- **Explore feed** (browse shared sets)
- **Share to Explore** (publish an immutable snapshot)
- **Short share links** (`https://learnhub.shaarav.xyz/share/ABC123`)
- **Save to My Sets** (clone as your own editable local set)
- **Basic moderation gate** before publish:
  - If Groq key exists, uses model `openai/gpt-oss-safeguard-20b`
  - Else uses Apple Intelligence

This guide is step-by-step for complete beginners.

---

## 0) What you need

- A free Supabase account
- Xcode project already running locally
- 10–15 minutes

---

## 1) Create Supabase project (free)

1. Open https://supabase.com
2. Create a new project (Free Plan).
3. Wait for database provisioning to finish.

Then copy API values:
1. Go to **Project Settings → API**
2. Copy:
   - **Project URL**
   - **anon public key**

---

## 2) Add Supabase keys to the app

Open `LearnHub/Info.plist` and fill:

- `SUPABASE_URL` = your project URL
- `SUPABASE_ANON_KEY` = your publishable key (`sb_publishable_...`) preferred

If these are empty, Explore will show a configuration error.

Security best-practice:
- Prefer the new publishable key format (`sb_publishable_...`) for client apps.
- Never use the service role key in iOS apps.
- Rotate keys in Supabase Dashboard if you suspect exposure.

---

## 3) Create/upgrade database table

Open **Supabase → SQL Editor** and run this script.

It supports both fresh setup and upgrading old schema.

```sql
create extension if not exists pgcrypto;

create table if not exists public.shared_study_sets (
  id uuid primary key default gen_random_uuid(),
  short_code text unique,
  title text not null,
  summary text,
  mode text not null default 'content',
  icon_id text not null default 'book',
  author_name text,
  publisher_id text not null,
  content_fingerprint text not null,
  created_at timestamptz not null default now(),
  is_public boolean not null default true,
  questions jsonb not null default '[]'::jsonb,
  flashcards jsonb not null default '[]'::jsonb
);

alter table public.shared_study_sets
  add column if not exists short_description text;

alter table public.shared_study_sets
  add column if not exists downloads_count integer not null default 0;

alter table public.shared_study_sets
  add column if not exists short_code text;

alter table public.shared_study_sets
  add column if not exists publisher_id text;

alter table public.shared_study_sets
  add column if not exists content_fingerprint text;

update public.shared_study_sets
set publisher_id = coalesce(publisher_id, gen_random_uuid()::text)
where publisher_id is null;

update public.shared_study_sets
set content_fingerprint = coalesce(content_fingerprint, md5(id::text || title || coalesce(summary, '')))
where content_fingerprint is null;

alter table public.shared_study_sets
  alter column publisher_id set not null;

alter table public.shared_study_sets
  alter column content_fingerprint set not null;

create index if not exists idx_shared_sets_created_at
  on public.shared_study_sets (created_at desc);

create index if not exists idx_shared_sets_is_public
  on public.shared_study_sets (is_public);

create index if not exists idx_shared_sets_publisher
  on public.shared_study_sets (publisher_id);

create unique index if not exists uq_shared_sets_publisher_fingerprint_public
  on public.shared_study_sets (publisher_id, content_fingerprint)
  where is_public = true;

create index if not exists idx_shared_sets_downloads
  on public.shared_study_sets (downloads_count desc, created_at desc);

create unique index if not exists uq_shared_sets_short_code
  on public.shared_study_sets (short_code)
  where short_code is not null;

create or replace function public.increment_download_count(set_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.shared_study_sets
  set downloads_count = downloads_count + 1
  where id = set_id
    and is_public = true;
end;
$$;

grant execute on function public.increment_download_count(uuid) to anon, authenticated;

create table if not exists public.review (
  id uuid primary key default gen_random_uuid(),
  shared_set_id uuid references public.shared_study_sets(id) on delete set null,
  reporter_id text not null,
  reason text not null,
  details text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- Optional one-time backfill for old rows without short_code.
-- App now auto-generates 6-char URL-safe codes for new publishes.
update public.shared_study_sets
set short_code = substring(replace(replace(encode(gen_random_bytes(6), 'base64'), '+', '-'), '/', '_') from 1 for 6)
where short_code is null;
```

What this gives you:
- `publisher_id`: device-level ownership id used by app
- `content_fingerprint`: dedupe key (prevents duplicate re-share)
- unique partial index: prevents re-publishing same content while public
- `short_code`: compact URL ID used in share links (`/share/{code}`)

---

## 4) Enable RLS + policies (MVP)

Run this next:

```sql
alter table public.shared_study_sets enable row level security;

drop policy if exists "anon read public shared sets" on public.shared_study_sets;
drop policy if exists "anon insert shared sets" on public.shared_study_sets;
drop policy if exists "anon update shared sets" on public.shared_study_sets;
drop policy if exists "anon delete own shared sets" on public.shared_study_sets;
drop policy if exists "anon insert review" on public.review;

create policy "anon read public shared sets"
on public.shared_study_sets
for select
using (is_public = true);

create policy "anon insert shared sets"
on public.shared_study_sets
for insert
with check (
  is_public = true
  and publisher_id is not null
  and content_fingerprint is not null
);

create policy "anon update shared sets"
on public.shared_study_sets
for update
using (true)
with check (true);

create policy "anon delete own shared sets"
on public.shared_study_sets
for delete
using (publisher_id is not null);

alter table public.review enable row level security;

create policy "anon insert review"
on public.review
for insert
to anon, authenticated
with check (
  reporter_id is not null
  and reporter_id <> ''
  and reason is not null
  and reason <> ''
);
```

Important note:
- This is **MVP security** for zero-friction free setup.
- Strong server-side ownership requires Supabase Auth + per-user JWT-backed RLS.

---

## 5) How app integration works (already coded)

The app already includes:

- `LearnHub/ExploreService.swift`
  - Fetch public sets
  - Publish snapshot with `publisher_id` + fingerprint dedupe
  - Sort by popularity via `downloads_count`
  - Increment popularity via `increment_download_count`
  - Submit reports into `review`
  - Unpublish (hard-deletes the row)
- `LearnHub/ExploreModerationService.swift`
  - Runs moderation before publish
  - Groq safeguard model if Groq key exists
  - Apple Intelligence fallback if no key
- `LearnHub/ExploreModels.swift`
  - Immutable shared DTO
  - Local clone builder for Save to My Sets

You do not need additional Swift code changes for the baseline flow.

For universal links to open directly in app, also deploy these web files:
- `website/.well-known/apple-app-site-association`
- `website/apple-app-site-association`
- `website/share/index.html`
- `website/_redirects` (Cloudflare Pages rewrite for `/share/*`)
- `website/404.html` (for static-host fallback of `/share/{code}` routes)

---

## 6) Test checklist

1. Run app
2. Home → switch to **Explore** tab
3. Open any local set → tap share icon
4. Confirm share screen and publish
5. Verify it appears in Explore on refresh
6. Open Explore item → tap **Save to My Sets**
7. Confirm new local clone appears in My Sets and is editable
8. If you support unpublish in your UI, verify the row is deleted from `shared_study_sets`

---

## 7) Moderation behavior

Before publish:

- If Groq API key exists in app settings:
  - Uses `openai/gpt-oss-safeguard-20b`
- If no Groq key:
  - Uses Apple Intelligence (if available)
- If moderation says unsafe:
  - Publish is blocked
  - User sees rejection reason and can edit content

---

## 8) Common issues

### Explore says “not configured”
- Fill `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `LearnHub/Info.plist`

### Publish fails with API error
- Re-check SQL table/columns/policies
- Ensure `publisher_id` and `content_fingerprint` columns exist and are `not null`

### Nothing appears in Explore
- Ensure row has `is_public = true`
- Pull to refresh Explore list

### Moderation unavailable
- Add Groq key in app settings, or enable Apple Intelligence on supported device

---

## 9) Cloudflare free alternative (if you want later)

You can use **Cloudflare Workers + D1** instead of Supabase:
- Build custom REST endpoints in Worker
- Store shared sets in D1
- Implement dedupe + moderation call server-side
- Implement your own auth/rate-limit/abuse protections

This is flexible, but significantly more backend work than Supabase for beginners.
