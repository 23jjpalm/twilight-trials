# Twilight Trials — GitHub Pages + Supabase Edition

A free-tier-friendly, static HTML/CSS/JavaScript speedrunning site with Supabase Auth, PostgreSQL, and server-enforced moderator permissions. **Starts with ZERO categories, ZERO runs, and ZERO demo accounts.** You do **not** run `python server.py`.

## 1. Create a Supabase project

1. Visit https://supabase.com/dashboard and create a new free project. Save the database password somewhere safe.
2. In the project's **SQL Editor**, open `supabase-setup.sql`, paste the **entire file**, and click Run **once on a fresh project**. The script creates tables, security policies, and RPC functions.
3. Go to **Authentication → Providers → Email** and keep Email enabled. Keeping **Confirm email** on is recommended. Supabase's built-in email sending may have trial/rate limits; for a larger public site, configure custom SMTP.
4. Go to **Project Settings → API** (some dashboard versions show **Connect → API Keys**) and copy your **Project URL** and **publishable key** (`sb_publishable_...` or legacy `anon` key).
5. Open `config.js` and replace the two placeholder strings with those values. **Never use `service_role` or `secret` keys.** The publishable key is intentionally safe to expose in frontend code when RLS is configured correctly.

## 2. Put your website on GitHub Pages

1. Create a new public GitHub repository, e.g. `twilight-trials`.
2. Upload these files to the **root** of the repository: `index.html`, `styles.css`, `app.js`, `data.js`, `config.js`. (You may also commit `README.md` and the SQL setup file.)
3. In GitHub: **Settings → Pages → Build and deployment**. Choose **Deploy from a branch**, then **main** and **/(root)**. Save.
4. Wait for the Pages deployment and open `https://YOUR_GITHUB_USERNAME.github.io/twilight-trials/`.
5. In Supabase: **Authentication → URL Configuration**: Set **Site URL** to the GitHub Pages URL above, and add that same URL to **Redirect URLs**. Include the trailing slash. If you later attach a custom domain, also update these URLs.
6. Register your personal account through the live site. If confirmations are enabled, click the link in your email, then sign in.

## 3. Make your account the administrator (one-time)

1. Go back to Supabase **SQL Editor** as project owner.
2. Execute, replacing `YOUR_USERNAME` with the username you registered:

```sql
update public.profiles
set role = 'admin'
where lower(username) = lower('YOUR_USERNAME');
```

3. Refresh the site (and sign in again if necessary). A **Dashboard** button appears. The dashboard lets you **Create category**, verify/reject runs, process community category proposals, edit/archive categories, and grant moderator status/ban accounts.
4. There is no default admin login or password. Accounts are handled by Supabase Authentication.

## 4. Moderator workflow

- New categories do not exist until a moderator creates or approves one.
- Create a category in **Dashboard → + Create category**. It appears on the site with an empty leaderboard.
- New users register with a unique public username, an email address, and a password. Supabase stores passwords; the website never handles password hashes.
- Runner submissions are forced to reference the signed-in user ID. All runs start `pending`.
- A moderator reviews proof and chooses **Verify** or **Reject**. Only verified runs show on public leaderboards.
- Admins can promote/demote other members through **Dashboard → Users**.
- Authz is enforced in PostgreSQL (RLS + security-definer RPCs), not only in JavaScript.

## 5. Editing the website later

- **Leaderboards, users, submissions, categories, rules**: edit within the website; writes are stored in Supabase automatically. You do **not** need to edit GitHub files.
- **Appearance, layout, new page features**: edit files in GitHub; Pages redeploys.
- **Adding more games**: edit the game list in `data.js` and update the SQL `categories.game` / `proposals.game` CHECK constraints. The game tabs themselves are not currently admin-editable.

## Important limitations / production considerations

- The site relies on the free Supabase plan. Supabase can pause inactive free projects, and usage limits apply. GitHub Pages serves static assets even if Supabase is temporarily unavailable.
- This is a frontend-only web app using Supabase APIs; no continuously running Python server is required.
- Secure RLS does not replace general abuse controls: before a public launch, consider CAPTCHA/rate limiting, an email sending service, backups, audit logs, and a privacy policy.
- The admin dashboard can **archive** categories (not physically delete them), preserving related runs.
- For consistent names, usernames cannot be changed in the frontend. Email is used for login; username is a public display name.
- Run records are stored by user ID rather than accepting a freely typed runner name.
- Video evidence is stored as an external HTTPS URL, not hosted video.
- Account email verification depends on your Supabase Auth settings. Signup will prompt users to check their email when needed.
- If you already have a local SQLite database with existing runs, **this package does not migrate it**. It deliberately starts empty.
- Supabase policies should be tested on your own project before inviting the public.

## Troubleshooting

**"Supabase is not connected"** — edit `config.js` with a valid Project URL and publishable key, then reload.

**"Failed to fetch"** — verify the Project URL, browser/network connectivity, and that the Supabase project is active.

**"new row violates row-level security policy"** — make sure you are logged in, not banned, and ran the whole `supabase-setup.sql` script.

**"Database error saving new user"** — pick a different unique username (letters, digits, underscore) and verify the signup trigger was installed.

**Dashboard button missing** — run the one-time admin SQL promotion, refresh, and confirm the username is correct.

**Site 404 on GitHub Pages** — make sure the repository's Pages setting is `main / (root)` and the `index.html` file is at the root.
