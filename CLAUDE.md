# Pangaea

One infinite map of ideas. Every person gets a plot; plots about related ideas gather into regions you can explore. A feed makes ideas vanish in a day; Pangaea gives every idea a lasting place.

This file is the source of truth: scope, rules, decisions and current state. `README.md` says how to run it; `docs/design.md` holds the visual system and the first-minute flow. Keep this file under 250 lines, the README under 60 and design.md under 150. Update these instead of adding new docs.

## 1. V1 scope and principles

**The two primary constraints are lowest running cost and maximum ease of use for customers.**

**Core loop (the funnel we measure):** a visitor explores the map without an account → opens plots → claims a plot → publishes something → visits a neighbor.

**V1 product**
- **Explore first.** The map is browsable without signing in. Sign-in appears only at "Claim your plot".
- **Sign-in.** "Continue with Google" is the main button; GitHub sits under "More options". No passwords, no email sign-in.
- **Creation.** One simple path: "What do you want to share?" → text, link or image → publish. Drawing and the full Excalidraw editor open only when the user asks. Templates appear after the first publish, not before.
- **The magic moment.** After publishing, the camera flies across the map and lands on their plot: "Welcome to [region]. Here are 3 nearby plots."
- **AI stays invisible.** Users never see words like embeddings, models or clustering.
- **Growth.** Plots grow slightly from signed-in visits and comments, and decay slowly. No missions yet.
- **New users' images** are visible on their own plot immediately, and become public (and appear in thumbnails) only after the batched check passes.

**Targets**
- Interesting content visible within 2 seconds, without an account.
- First content published within 30 seconds of signing in.
- An idle platform costs about $5 a month. Public browsing is effectively CDN-only. A new user costs pennies or less. A normal edit costs near zero unless moderation or embedding is needed. Background work is incremental, never a global rescan.

**Delayed until measured need:** missions, cold storage, complex growth formulas, live webpages, continents, code cards, item types gated by trust level, the tile pyramid.

**Rules for every feature**
- Cost order: deterministic code → database → browser → cached result → cheap model → expensive model. AI is the fallback, never the default.
- Every feature must answer yes to three questions: does it make Pangaea easier for the customer, does it improve the core experience, and is it worth its running and support cost? If not clearly yes, don't build it yet.
- If a choice adds recurring cost, stop and tell the owner the cost and the free alternative first. Stay on free tiers through development.

## 2. Product rules (do not change without asking)

- One plot per user; only the owner edits it. Visitors view and comment. Space is never sold.
- Signup asks for a handle and a one-line plot description (editable anytime, moderated like any text).
- **Nothing appears publicly until it passes moderation.** No exceptions, including seed data.
- Never allowed: nudity or sexual content, gore, hate, harassment, self-harm promotion, scams, malware, illegal content.
- Placement is by topic and stable: a plot moves only when its content clearly changes topic. If it can't be placed, the owner picks a region from a list.
- Plot owners can delete comments on their plot; deleted comments stay stored for moderators.
- Signed-out views count for display only. Only signed-in visitors contribute to growth.
- Moderation messages are kind and clear: what was blocked, why, and an appeal button.
- Notifications only for things that matter (a comment, your plot grew or shrank).

## 3. Engineering rules

- Build only what the current phase needs. Future plans are one line each in section 9.
- No abstraction until something is used in two places. Inline small helpers used once. Prefer one clear file over several tiny ones: a file under about 20 lines used in one place probably belongs inside another.
- Comments explain why, never what. Generated files say so on their first line.
- TypeScript strict; no `any` without an inline comment saying why. No hard-coded user-facing strings: use `messages/<locale>.json` (next-intl).
- Never commit or log secrets, tokens, dumps or personal data. Keys come from env vars or Wrangler secrets.
- Keep Worker requests light (free plan: 10 ms CPU per request). Prefer static pages and client rendering; heavy work goes in the browser or in cron batches.
- Tests protect real behavior. Database security tests (`supabase/tests`) cover RLS, ownership and the moderation pipeline; unit tests (Vitest) cover pure logic; providers sit behind interfaces with fakes, so no test calls a paid API.
- At the end of every phase:
  1. Run all checks and confirm CI passes.
  2. Run a code review and a security review (auth, RLS, moderation, anything running user content).
  3. Report Lighthouse numbers against the budgets in `docs/design.md`.
  4. List the skills and tools used.
  5. Give a 5-person usability test script.
  6. Stop for the owner's review.
- Use the available skills and tools (design, accessibility and UX-copy skills, code and security review, Playwright) instead of working from memory. Ask before installing anything paid or anything that needs the owner's credentials.

## 4. Stack and decisions

Each line: what we chose, and why.

- **Next.js App Router + TypeScript + Tailwind on Cloudflare Workers via OpenNext.** Static assets are free and unlimited, and there is no egress fee. Vercel's free plan forbids commercial use. Free plan in development; **Workers Paid ($5/month) at public launch**. Measure CPU per route with Workers Observability.
- **Pages render statically** (static-assets cache, no ISR). No `images` binding: Cloudflare Images is metered, and images are resized in the browser.
- **Supabase free plan** (Postgres + Auth). Sign-in with Google and GitHub only, so there is no email cost.
- **Safety is enforced in the database.**
  - RLS on every table, with privileges granted per column, so clients can't write moderation, trust or growth fields.
  - Guard triggers send edited content back to review.
  - The public reads items and comments only through `plot_items_public` / `comments_public`, which return approved rows; reported rows keep their slot with content withheld.
  - Privileged helpers live in a `private` schema the API doesn't expose.
- **Cloudflare R2 behind the CDN for all media and map data** (no egress fees), reached only through the S3 API so the vendor can be swapped. Locally, Supabase Storage stands in for it.
- **Content-addressed media.** Files are keyed by SHA-256: stored once and moderated once. Uploads go to a presigned, single-use key (`incoming/<user>/<id>`). The server verifies the hash, then copies the file to its content address.
- **Images are processed in the browser.** Resize to at most 1,024 px, encode WebP (JPEG as last resort), strip metadata, keep only the first frame of a GIF. This means no server image CPU and cheap Claude checks.
- **Thumbnails are rendered in the owner's browser** and are untrusted. One is published only after it passes image moderation and every item it shows is approved.
- **Moderation, cheapest first:**
  1. A known approved hash is reused.
  2. Abuse-hash matching (PhotoDNA, required before launch).
  3. OpenAI Moderation (free). For images it covers only sexual content, violence and self-harm.
  4. Claude Haiku (`claude-haiku-4-5-20251001`, env `ANTHROPIC_MODEL`) checks the exact stored image bytes, including text inside the image, for all banned categories. It runs on images from trust-level-0 users, images on plots that start earning growth, and reported images, and records a short description for placement.
  5. Borderline text goes to Claude, then humans.

  Batch API unless a person is waiting. A daily spend cap (`ai_spend_daily`) makes work wait; it never skips a check.
- **Reports are weighted by trust:** a level 2 report blurs immediately; level 1 counts 0.5 and level 0 counts 0.25 toward a total of 1.0. Every report triggers an automated re-check.
- **Appeals** are only for your own rejected or blurred content, one open appeal at a time.
- **Placement uses direct embeddings,** with no summary step. Voyage `voyage-4-lite` embeds the description, text and image descriptions, at 512 dimensions stored as `halfvec` (about 1 KB per plot). Re-embed only when a hash of that text changes, after about 10 quiet minutes. Claude names each new region once, and the label is cached forever.
- **Growth is computed on read.** `earned_space` plus a timestamp, decayed in closed form (30-day half-life); no job ever touches every plot. The browser batches views and dwell time about every 30 seconds into `attention_daily` (one row per plot, visitor and day), with an exact per-visitor daily cap.
- **Map without a tile pipeline.**
  - Zoomed out: vector regions and plot blocks, from small cached layout JSON chunks.
  - Mid zoom: viewport thumbnails through a texture cache.
  - Close zoom: the plot's published snapshot JSON.
  - The viewer never loads the editor.
- **Editor:** Excalidraw (MIT), lazy-loaded only on request. Saves are debounced and only send changed elements, with an offline queue. No real-time sync.
- **Background work** runs on Cloudflare Cron Triggers calling our routes in small batches. A cron is registered only once its job exists. GitHub Actions is for CI only: GitHub's terms limit hosted runners to building, testing and deploying.
- **Backups (launch):** a nightly Worker cron streams `COPY` per table, then gzips it, encrypts it with AES-GCM under a key wrapped by an RSA public key, and writes it to private R2. The private key stays offline. Supabase's free plan has no backups.
- **i18n:** next-intl with the locale fixed per build, so pages stay static. Hindi will arrive as a static `/hi` route. IBM Plex covers Devanagari.
- **Analytics:** Cloudflare Web Analytics (free, cookieless). PostHog's free tier only if funnels need it, with a $0 billing limit.

## 5. Data model (V1)

The schema is `supabase/migrations/20261006000000_initial.sql`. New features add new migrations.

| Table | Notes |
| --- | --- |
| `users` | handle, trust_level 0–2 |
| `staff` | private moderator and admin membership |
| `regions` | label named once, color_slot 1–8, `halfvec(512)` centroid, single frontier |
| `plots` | one per user; placement kind, grid cell, base_size + earned_space (decays on read), text_hash and embedding, thumbnail asset and ThumbHash, snapshot_version, display_view_count; clients read only map columns |
| `plot_items` | description (exactly one, never deleted), text, link, image, drawing. Content is moderated; position holds only numeric layout fields; images must reference an asset the owner uploaded |
| `assets`, `asset_sources`, `asset_uploads` | content-addressed media, browser-side hash of the original file, ownership |
| `comments` | moderated; soft delete via `delete_comment()` by the author or the plot owner |
| `attention_daily` | server-only growth input |
| `reports`, `appeals` | trust-weighted reports; appeals limited to your own decided content |
| `ai_spend_daily` | Claude spend ledger for the daily cap |

## 6. Current state

**Phase 0 (setup): done.**
- Next.js 16 on Cloudflare via OpenNext, with security headers and a static, translated home page.
- Design tokens and self-hosted IBM Plex.
- The V1 schema with 61 database security tests.
- Env validation, and Supabase browser, server and admin clients.
- CI runs lint, typecheck, format, unit tests and the Workers build, plus migrations, database tests, the database linter and a generated-types check.
- Lighthouse mobile: performance 100, accessibility 100, LCP 1.7 s, TBT 58 ms.

**Phase 1: claim and publish (next).**
- "Claim your plot" with Google/GitHub sign-in, then handle and description, then plot created.
- The composer: "What do you want to share?" → text, link or image → publish.
- Browser image processing and uploads, with optimistic "in review" items.
- The moderation pipeline: OpenAI, then batched Claude image checks under the cap, kind messages and appeals. This includes the first cron job.
- A plot page.

**Phase 2: explore.**
- The map is browsable without an account: vector layout, viewport thumbnails, snapshots.
- Open a plot.
- The fly-in "Welcome to [region]. Here are 3 nearby plots."
- A seed script whose fake plots go through moderation.
- Funnel analytics.

**Phase 3: placement.** Embeddings, region assignment, the frontier, owner-chosen regions, labels named once.

**Phase 4: community and growth.** Comments, signed-in attention, slight growth and decay, trust-weighted reports and the admin page, templates after first publish, drawing on request, web push.

## 7. Launch checklist (owner; required before public launch)

- **Spending caps and alerts** (verify each dashboard when you set it):
  - Anthropic: Settings → Billing → Spend limits, with prepaid credits and auto-reload off.
  - OpenAI: a project limited to moderation, with its budget at $0 or minimal.
  - Voyage: a hard limit if offered, otherwise our app enforces a monthly budget.
  - Cloudflare: billing alerts. R2 has no hard cap, so our per-plot and per-user limits are the cap.
  - Supabase: keep Spend Cap on if on Pro.
  - PostHog (if used): billing limit $0.
  - GitHub Actions: spending limit $0.
- **Abuse-material hash matching:** PhotoDNA Cloud Service wired into moderation before publishing, plus Cloudflare's CSAM Scanning Tool (free) as a second layer.
- **Legal reporting** (confirm with a lawyer):
  - **US:** report apparent CSAM to NCMEC's CyberTipline and preserve the report (18 U.S.C. § 2258A).
  - **India:** POCSO Act §19–20 and IT Act §67B. Under IT Rules 2021, publish a Grievance Officer, acknowledge complaints within 24 hours and resolve them within 15 days, and remove intimate content within 24 hours of a complaint. Report through cybercrime.gov.in.
  - Write down the internal procedure: who reports, how fast, and how evidence is preserved and restricted.
- Terms of service, a privacy policy (naming the AI processors: Anthropic, OpenAI, Voyage) and a content policy.
- Workers Paid enabled and CPU per request measured. Nightly encrypted backups running, with one restore tested. OAuth apps in production mode. Domain, CDN and Web Analytics configured. Deploy checklist run.
- **Supabase free projects pause after a week without activity.** The moderation cron keeps it active; confirm before launch.

## 8. Cost notes

Assumptions per active user per month:
- 8 visits and about 300 app requests
- 4 images and 4 thumbnails
- about 2 MB stored
- about 35 moderation checks, 2% of them borderline

A Claude image check of a 1,024 px image costs about $0.0009 through the Batch API. Prices are as of October 2026; re-check before launch.

| Part | Idle | 1,000 active users / month | 100,000 active users / month |
| --- | --- | --- | --- |
| Cloudflare Workers | $5 (Paid, from launch) | $5 | ~$12 |
| R2 + CDN | $0 | $0 (free allowance) | ~$16 |
| Supabase | $0 | $0 | $25 (Pro: over 500 MB or 50k users) |
| Voyage embeddings | $0 | $0 (one-time 200M free tokens) | ~$6 |
| OpenAI Moderation | $0 | $0 | $0 |
| Claude image checks (batch) | $0 | ~$3 | ~$320 |
| Claude borderline text + region names | $0 | ~$1 | ~$70 |
| Domain | ~$1 | ~$1 | ~$1 |
| **Total** | **~$6** | **~$10** | **~$450** |

Paid first, in order:
1. Workers Paid ($5), at launch.
2. Anthropic: a small prepaid credit, since it has no free tier.
3. Supabase Pro ($25), at about 15–20k plots or 50k users.

The biggest lever is Claude image checks for new users. Promote trustworthy users out of level 0 sooner, skip thumbnails whose images have all already passed, and tune the daily cap.

## 9. Later (one line each; build only when the trigger is met)

- **Tile pyramid:** when zoomed-out panning drops below 60 fps or the first view's map data passes 150 KB gzipped on a mid-range phone (estimated at about 250k plots). It would composite on Workers Paid; never on GitHub Actions or in users' browsers.
- **Cold storage:** move plots idle for 90 days to R2, when the database nears 500 MB.
- **Missions:** when the core loop is healthy and retention needs a push.
- **Continents:** group regions into continents once there are enough regions to need a level above them.
- **Code cards:** Excalidraw image elements we render, with the source in `customData` and HTML overlays in the viewer.
- **Trust-gated item types** (webpages, video), with live webpages shown as a screenshot plus a sandboxed iframe on a separate origin after a security review.
- **Hindi:** a static `/hi` route and a catalog with the same keys as `en.json`.
- **Owner activity pausing decay:** only if simple decay proves unfair.
- **Region Open Graph images:** default to the thumbnail of the region's most-visited plot.

---

Next.js version notes for coding agents: @AGENTS.md
