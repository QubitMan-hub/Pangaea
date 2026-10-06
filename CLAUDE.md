# Pangaea: Build Brief for Claude Code

Read this whole file before writing any code. It is the source of truth for this project. Details live in `docs/architecture.md` (how it works), `docs/decisions.md` (why), `docs/design.md` (how it looks and feels) and `docs/testing.md` (how we know it works). Where any of them disagrees with this file, this file wins.

## 1. What we are building

Pangaea is "Reddit, but as one giant whiteboard." It is one infinite whiteboard shared by the whole world. Every user gets a small plot on it to share ideas, drawings, images, links, code snippets and (later) live webpages. Pangaea reads each plot and places it next to plots with related ideas, so the board forms "continents" of topics on its own. Plots grow by completing missions and earning genuine attention, and earned space slowly decays so newcomers can always compete.

Core feeling: a feed makes ideas vanish in a day. Pangaea gives every idea a lasting place on a map you can explore. It should feel as smooth as Google Maps and as polished as Linear or Figma.

## 2. Top priority: lowest possible running cost

Running cost is the most important constraint on this project right now.

- For every technical decision, pick the cheapest option that works reliably.
- Stay inside free tiers for as long as possible. Development stays entirely on free plans.
- **If a choice would add recurring cost, stop and tell me the cost and the free alternative before doing it.**
- Nothing in the UI or UX work may add recurring cost.
- Most visitors only look. Looking must cost almost nothing (static files from a CDN, no database). Expensive work runs only when something actually changes, and only for what changed.

### 2.1 Cost rules (hard requirements)

1. **Map rendering without a tile pipeline (for now).**
   - Zoomed out: regions drawn as vector shapes with labels, and plots as simple blocks, from a small cached JSON of the map layout.
   - Mid zoom: PixiJS loads moderated plot thumbnails only for plots in the viewport, with a texture cache that unloads off-screen ones.
   - Close zoom: full plot content, only for plots on screen.

   A pre-rendered tile pyramid is a future phase, triggered by measurement (section 14).
2. **Level of detail.** Never load the editor or full plot contents when zoomed out. Live webpages show a static screenshot with a "tap to run" button and load only when tapped.
3. **Thumbnails** are rendered in the owner's browser when they save, then uploaded. We pay no server compute for them. A thumbnail is moderated like any other image (7.4).
4. **Uploads.** The browser compresses and resizes images to **WebP** (JPEG only for browsers that can't encode WebP) and strips metadata. Every file is hashed and duplicates are stored once. Drawings are stored as simplified, compressed stroke data.
5. **Per-plot limits.** Cap total storage and the number of items per plot (defaults in 7.5).
6. **Placement.** Embed each plot's description, its text and the stored image descriptions directly with Voyage (free tier). There is no separate summary step. Claude only names new regions and continents: once each, label cached forever. Model `claude-haiku-4-5-20251001` from env var `ANTHROPIC_MODEL`. Batch API for anything not urgent.
7. **Re-embed only on meaningful change** to that text.
8. **Never rescan a file whose hash was already approved.** This applies separately to each check: once a hash has passed the Claude image check, it never needs that check again.
9. **Growth and decay.** No scheduled job over all plots. Store `earned_space` with a last-updated timestamp and compute decay at read time with a closed-form formula.
10. **Attention.** The browser batches views and dwell time and sends them roughly every 30 seconds.
11. **No real-time sync servers.** Only owners edit their plots, so saves are debounced.
12. **Cold storage.** A plot with no visits for 90 days moves its full content to R2. Its thumbnail stays on the map. It comes back automatically when its owner edits it or someone opens it.
13. **Spending caps.** Every paid or metered service has a hard monthly limit and a usage alert, set before launch (section 12).
14. **Hosting plan.** Develop on Cloudflare Workers Free. Plan for **Workers Paid ($5/month) at public launch**. Measure real CPU per request (Workers Observability, free) so we know when we hit the free limit.

## 3. Product rules (do not change without asking)

- One plot per user. Only the owner can edit their plot. Visitors can view, react and comment.
- Users sign in with Google or GitHub, pick a handle, and write a one-line plot description at signup. The description can be edited anytime and is moderated like any text.
- Space on the public board is never sold. Growth only comes from missions and attention.
- Nothing appears publicly until it passes moderation. No exceptions, including in dev seed data shown to real users.
- Never allowed: nudity or sexual content, gore, hate, harassment, self-harm promotion, scams, malware, illegal content.
- Plots are placed by topic, and placement must be stable. A plot only moves if its content clearly changes topic. If a plot can't be placed automatically, its owner picks a region from a list.
- Earned space decays over time unless the owner stays active.
- Plot owners can delete comments on their own plot. Deleted comments disappear for everyone else but stay stored for moderators.
- Signed-out visitors' views count for display only. Only signed-in visitors contribute to growth.
- Moderation messages are kind and clear: what was blocked, why, and an appeal button.
- Notifications only for things that matter (a comment, your plot grew or shrank) plus an optional weekly digest. No spammy notifications.

## 4. Experience requirements

Full detail and targets are in `docs/design.md`. These are the non-negotiables.

- **Design first.** `docs/design.md` defines a distinctive "living atlas" identity: color tokens with light and dark themes, typography, spacing, motion and core components. Each region has its own color. The map must be beautiful fully zoomed out, because zoomed-out screenshots are our best marketing. Show the owner the design direction before building full screens.
- **The first minute.** Sign in with Google or GitHub, pick a handle, write a one-line description, add one thing (paste a link, drop an image or pick a template). Then the camera flies across the world and lands on the new plot in its neighborhood, showing the neighbors. The whole flow takes under 60 seconds. Templates: game project, portfolio, startup idea, research, art.
- **Zero-friction posting.**
  - Paste anywhere (Ctrl+V or long-press) and the type is detected: a URL becomes a link card, code becomes a code card with its language detected, an image becomes an image.
  - Drag and drop files onto the plot.
  - Installable PWA, registered as a share target.
  - Optimistic UI: new items appear instantly for the owner with an "in review" badge.
  - A free, deterministic "tidy up" button arranges a messy plot.
- **Effortless navigation.**
  - 60fps pan and zoom with momentum, pinch to zoom, smooth fly-to animations.
  - A command palette (Cmd/Ctrl+K) to search people, topics and regions and fly there.
  - Breadcrumbs (continent → region → plot), a minimap and the "wander" button.
  - Clean shareable URLs for every plot and region, with Open Graph images from existing thumbnails.
  - Keyboard shortcuts with a "?" overlay.
- **Mobile first.** Thumb-reachable controls, bottom sheets, large touch targets. Desktop gets more space, not a different product.
- **Feedback.** Skeleton loaders and tiny blurred placeholders (ThumbHash) instead of blank boxes. Free web push notifications.
- **Speed budgets** are hard targets, checked every phase with Lighthouse and reported (numbers in `docs/design.md`).
  - The world viewer ships minimal JavaScript.
  - The Excalidraw editor is lazy-loaded only when someone edits their own plot.
  - Saves queue locally and retry on flaky connections.
- **Accessibility and reach.**
  - Full keyboard navigation and screen reader support.
  - A "list view" of any region.
  - Reduced-motion mode, good contrast, and alt-text prompts for images.
  - Internationalization from the start, so Hindi and other languages need no rewrites.
- **Measuring UX.** Cloudflare Web Analytics, plus PostHog's free tier only if we need event funnels, with its billing limit at $0. Track the first-minute funnel, return visits and neighbor exploration.

## 5. Tech stack

Use these unless there is a strong reason not to. If you want to deviate, stop and ask first.

- **App:** Next.js (App Router) + TypeScript (strict mode) + Tailwind, on **Cloudflare Workers via OpenNext** (`@opennextjs/cloudflare`). Not Vercel: its free plan doesn't allow commercial use. If Next.js on Cloudflare causes real problems, tell me before switching.
- **Plot editor:** **Excalidraw** (MIT). tldraw is not used anywhere.
  - Excalidraw has no API for custom element types, so code cards and link cards are Excalidraw image elements that our code renders. Their source is stored on the element (`customData`) and edited through our own dialog.
  - In the plot viewer (not the editor), real HTML is overlaid on those cards when zoomed in, so code can be selected and copied and links clicked.
  - If Excalidraw can't support something else we need, tell me instead of working around it silently.
- **World viewer:** our own, built with **PixiJS** (WebGL). View only.
- **Database and auth:** **Supabase**, free plan. Postgres with pgvector. Sign-in with Google and GitHub only.
- **Object storage and CDN:** **Cloudflare R2** behind Cloudflare's CDN (no egress fees) for images, thumbnails, layout JSON, plot snapshots, cold storage and backups. The app talks to it only through the S3 API. Locally, Supabase Storage's S3 endpoint stands in for it.
- **Background work:** **Cloudflare Cron Triggers** calling our routes, each run processing a small batch. Move to an always-on container only when volume justifies it, and ask me first. **GitHub Actions are only for CI** (building, testing, deploying). GitHub's terms forbid using hosted runners for unrelated production work.
- **Embeddings:** Voyage AI `voyage-4-lite` (env `VOYAGE_MODEL`), 512 dimensions stored as `halfvec(512)`.
- **AI:** Anthropic API, `claude-haiku-4-5-20251001` (env `ANTHROPIC_MODEL`), for:
  - naming new regions and continents
  - borderline moderation
  - image checks (7.4)

  Use the normal API when a person is waiting, and the Batch API otherwise.
- **Moderation:** **OpenAI Moderation API** (`omni-moderation-latest`, free) for text and images, behind one `ModerationService` interface. Claude (Haiku) handles the image checks in 7.4 and borderline cases, under a daily spend cap. Humans handle the rest. **Abuse-material hash matching is required before public launch** (section 12).
- **i18n:** `next-intl` with message catalogs, no hard-coded user-facing strings.
- **Analytics:** Cloudflare Web Analytics (free, cookieless). PostHog free tier only if funnels need it.
- **Placeholders:** until the Cloudflare account and domain exist, use placeholder env vars.

## 6. Data model (starting point, refine as needed)

- `users`: id, handle (picked at signup), created_at, trust_level (0 new, 1 established, 2 trusted)
- `continents`: id, label (named once by Claude, cached forever), color
- `regions`: id, continent_id, label (named once, cached forever), color, centroid_embedding halfvec(512), center_x, center_y, plot_count, is_frontier
- `plots`: id, owner_id, region_id, placement (auto, owner_chosen, unplaced), grid_x, grid_y, base_size, earned_space, earned_space_updated_at, last_active_at, last_visited_at, text_hash, embedding halfvec(512), thumbnail asset, thumb_hash (tiny blur placeholder), snapshot version, cold_storage_key, display_view_count, status
- `plot_items`: id, plot_id, type (description, text, drawing, image, link, code, webpage, video, document), content (json, including a card's source text), position (json), asset_sha256, moderation_status (pending, approved, rejected, blurred), moderation_reason, created_at. Exactly one `description` item per plot.
- `assets`: sha256, mime_type (`image/webp`, or `image/jpeg` as the last-resort fallback), byte_size, width, height, moderation_status, claude_checked_at, ai_description (short description from Claude, used for placement and as fallback alt text)
- `missions`, `mission_completions` (as before)
- `attention_daily`: plot_id, visitor_id, day, views, dwell_seconds, is_return_visit, credited_score (signed-in visitors only; rows older than about 35 days deleted)
- `comments`: id, plot_id, author_id, body, moderation_status, deleted_at, deleted_by, created_at
- `reports`: id, target_type, target_id, reporter_id, reporter_trust_level, weight, reason, status, created_at
- `appeals`: id, target_type, target_id, user_id, message, status, created_at
- `ai_spend_daily`: day, purpose, requests, input_tokens, output_tokens, estimated_cost_usd (enforces the daily Claude cap)
- Later phases: `push_subscriptions`, `notification_prefs`

Enable Row Level Security everywhere. Only owners can write to their own plot and items.

## 7. Key systems

### 7.1 Placement

1. When a plot's approved text changes meaningfully (7.9), embed it with Voyage. "Text" means the description, text items, card source text and the image descriptions. Embed at most ~2,000 tokens, description first.
2. Find the nearest region by cosine similarity on `centroid_embedding`. If it's close enough, place the plot at the nearest free grid cell, spiraling out from the region center.
3. Otherwise hold the plot in the frontier region. When enough similar frontier plots exist, create a new region and ask Claude (Batch API) for its label once. Regions are grouped into continents the same way.
4. If a plot still can't be placed (for example the frontier is crowded or the text is too short), the owner picks a region from a list. This is stored as `placement = owner_chosen`, and automatic placement then leaves it alone unless the owner asks.
5. Re-check placement only when the new embedding is far from the old one. Never reshuffle the whole map.

### 7.2 Growth and decay

- Plot size = base_size + earned_space. Earned space comes from mission points and attention from signed-in visitors. Dwell time, comments and returning visitors count far more than raw views, with a per-visitor daily cap.
- Exponential decay with a 30 day half-life (configurable), computed on read:
  `earned(now) = earned_space × 2^(−max(0, now − max(earned_space_updated_at, last_active_at + grace)) / half_life)`.
- Adding points sets `earned_space = earned(now) + points` and the timestamp to now. Owner activity brings earned space up to date before moving `last_active_at`.
- **Before a plot's first growth applies, every image on it must have passed the Claude image check (7.4).** Credits are held until then.
- Footprints change in steps; only plots crossing a step are updated. Changing size must never overlap neighbors. Pick a simple approach and explain it.

### 7.3 Missions (MVP set)

1. Leave thoughtful comments on three neighboring plots.
2. Answer a question someone pinned on their plot.
3. Visit a region you have never visited and leave a note.
4. Complete your plot with at least three items.

Verify completions automatically where possible. Low-effort comments don't count (simple quality check).

### 7.4 Moderation pipeline

1. Every new item, comment, description, image and thumbnail starts `pending`. Only its owner sees it, with an "in review" badge.
2. **Text** (items, comments, descriptions, card source text) goes through OpenAI Moderation. Borderline results go to Claude within the daily cap, and whatever Claude can't decide goes to humans.
3. **Images and thumbnails** go through OpenAI Moderation (it covers sexual content, violence and self-harm). Claude (Haiku) then also checks the image, including any text inside it, for all banned categories, in three cases:
   - **Every image from a trust level 0 user.** Normal API, so new users aren't stuck waiting.
   - **Every image on a plot once it starts earning growth from attention**, before the growth applies. Batch API.
   - **Any reported image.** Batch API, unless the report blurred it (then normal API).

   Each check also asks Claude for a short image description, stored on the asset for placement and as fallback alt text.
4. **The daily cap is never a bypass.** If the Claude cap is reached, images that need a Claude check stay pending until budget is available or a human reviews them.
5. A hash that has passed a check is never rescanned for that check.
6. **Code and link cards:** the card's source text is moderated as text. The card image the browser renders is never shown publicly on its own; the public viewer draws cards from their moderated source. Thumbnails that include cards are moderated as images.
7. **Thumbnails** are untrusted. One is published only if it passes image moderation (including Claude where 7.4.3 applies) **and** every item in the scene it was rendered from is already approved.
8. Approved content goes public. Rejected content stays private with a kind, clear reason and an appeal button.
9. **Trust levels:** level 0 can post text, drawings, images, links and code; webpages and video unlock at level 1. Promotion rules are documented in `docs/architecture.md`.
10. **Reports are weighted by trust.**
    - A trusted (level 2) user's report blurs the content immediately.
    - Reports from newer users add up toward a threshold that blurs it.
    - Every report triggers an immediate automated re-check; if that flags the content, it is blurred right away.
11. A minimal admin page reviews reports, borderline items and appeals.
12. Links: store them, show preview cards, and recheck destinations on a schedule (small cron batches).
13. **Abuse-material hash matching** sits in `ModerationService`. It must be live before public launch (section 12).

### 7.5 Uploads, media and limits

- The browser resizes images (longest side at most 1,024 px), encodes WebP (JPEG last resort), strips metadata and keeps only the first frame of GIFs. 1,024 px keeps storage and Claude image checks cheap while staying sharp at plot zoom.
- The browser hashes the original file. If that hash maps to an existing asset, nothing is uploaded.
- Otherwise it uploads to a presigned URL for a **single-use key unique to that upload** (`incoming/<user id>/<upload id>`), with a signed size cap.
- The server then verifies the bytes' hash and copies them to their content-addressed key. Nobody can overwrite someone else's verified file.
- Content-addressed keys in R2, with immutable caching for approved media.
- Drawings: strokes simplified (Ramer–Douglas–Peucker), coordinates quantized and delta-encoded.
- Default limits (configurable):
  - per plot: 10 MB of stored media including the thumbnail, 30 images, 2,000 drawing elements, 1 MB of scene data
  - per user: 30 uploads a day

### 7.6 World viewer

- **Map layout JSON:** a small file per spatial chunk (plot id, position, size, region, ThumbHash), plus a regions file (shapes, colors, labels). Both are rebuilt in small cron batches when placement or sizes change, served from R2 with short caching and versioned names.
- **Zoomed out:** vector region shapes and labels, and plot blocks. Mid zoom: thumbnails for plots in the viewport, with a texture cache that unloads off-screen textures. Close zoom: the plot's published snapshot (approved items as JSON), with media loaded only for items on screen, and HTML overlays for cards.
- **Takedowns:** rejecting or blurring content removes it from the next snapshot and layout build right away (priority). For serious content, old objects are deleted and purged from the CDN.

### 7.7 Editing and saving

- Excalidraw scene, saved debounced (about 1 to 2 seconds after the last change), sending only changed elements, plus a final save when the page is hidden.
- Saves queue locally (IndexedDB) and retry on flaky connections. No live sync; with two tabs open, the last write to each element wins.
- "Tidy up" is a deterministic layout function in the browser. No server, no AI.

### 7.8 Auth

- Google and GitHub sign-in only (no email delivery cost). The local dev stack may use email sign-in through its built-in test mailbox; that never reaches production.

### 7.9 AI and embedding spend

- **Meaningful change:** normalize the plot's approved text and hash it. If the hash equals `text_hash`, do nothing. Otherwise wait until the plot has been quiet for about 10 minutes, then re-embed. Batch many plots per Voyage request.
- Every Claude call (labels, borderline checks, image checks) is recorded in `ai_spend_daily` and stops at the daily cap (`CLAUDE_DAILY_BUDGET_USD`).
- Claude always checks **the exact stored bytes** of an image (at most 1,024 px), never a separate copy supplied by the browser, so what was checked is exactly what gets published.

### 7.10 Attention

- The browser counts views and visible, focused dwell time while a plot is open, and sends them about every 30 seconds and when the page is hidden (`sendBeacon`).
- The server ignores owners viewing their own plot, caps dwell at the real time since that visitor's last report, folds each batch into `attention_daily`, and credits `min(daily cap, score) − credited_score`.
- Signed-out visitors only increment the display view count, at most once per plot per visit. `last_visited_at` is updated at most once per plot per day.

### 7.11 Cold storage

- A Cron Trigger finds plots whose `last_visited_at` is older than 90 days through an indexed query, in small batches. It writes their full content to R2 (standard storage class) and removes the content rows from Postgres.
- The thumbnail, layout entry and published snapshot stay. An owner edit or a visitor opening the plot restores it.

### 7.12 Backups

- Nightly, a Cron Trigger on our Worker streams each table out of Postgres (`COPY … TO STDOUT` over a direct connection) and gzips it. It then encrypts it with a fresh AES-256-GCM key that is wrapped with an RSA-OAEP **public** key, and writes it to a private R2 bucket. The private key never touches Cloudflare; the owner keeps it offline. The schema is restored from the migrations in git.
- This needs Workers Paid for CPU time, which is already planned for launch, so it adds no cost. During development there are no backups of production data, because there is none yet.
- Never log dump contents, keys or connection strings. Retention: 7 daily and 4 weekly copies, using R2 lifecycle rules.

### 7.13 Live webpages (Phase 6 only)

- Static screenshot (an asset, moderated like any image) with "tap to run". On tap, serve the HTML from a separate origin, inside a sandboxed iframe with a strict Content Security Policy.
- No access to the parent page, cookies or visitor data. No pop-ups, no top-level navigation. Size limits per plot.
- Write a security review checklist before enabling this publicly.

## 8. Build phases

Work one phase at a time. **At the end of each phase:**

1. Run all tests.
2. Run a code review and a security review: take extra care with auth, Row Level Security, the moderation pipeline and anything that runs user-provided content.
3. Report Lighthouse numbers against the speed budgets.
4. Summarize what was built and list anything you were unsure about.
5. List the skills and tools used.
6. Give a 5-person usability test script (tasks and what to watch for).
7. Stop for my review.

**Phase 0: Setup.** Repo structure, Next.js on Cloudflare via OpenNext, Supabase schema and migrations, env template, lint, formatting, tests, i18n and design-token foundations, README. (Being reworked for this brief.)

**Phase 1: Plots and the first minute.**
- Google/GitHub sign-in, handle and description at signup, and plot creation.
- The Excalidraw editor (lazy-loaded) with text, drawings, images, link and code cards.
- Paste and drag-drop detection, templates, "tidy up".
- Debounced saves with an offline queue, browser image processing and thumbnails, per-plot limits.
- The moderation pipeline including Claude image checks, kind moderation messages and appeals.
- The installable PWA with share target.

**Phase 2: The world map.**
- PixiJS viewer (vector layout, viewport thumbnails, snapshots with card overlays), region colors and labels.
- The camera fly-in to a new plot, the command palette, breadcrumbs, minimap and "wander".
- Shareable URLs with Open Graph images, keyboard shortcuts, and the region list view.
- Measure the viewer at scale (section 14).

**Phase 3: Placement.** Voyage embeddings of descriptions, text and image descriptions; region and continent assignment; frontier; labels named once by Claude; owner-chosen regions; stable placement.

**Phase 4: Growth.** Batched attention, missions, decay on read, Claude checks before growth, resizing without overlaps, cold storage, web push notifications and the weekly digest.

**Phase 5: Safety and polish.** Trust-weighted reports with automated re-checks, blur on report, admin review page, trust promotion, rate limits, link rechecks, owner comment deletion, abuse-material hash matching, backups, the launch checklist.

**Phase 6 (later):** Live webpages, video, private islands, plot cosmetics, and the tile pyramid if section 14's trigger fires.

## 9. Not in the MVP

Real-time multi-user editing, plot merging, payments, mobile apps, private islands, video, live webpages, the tile pyramid. Do not build these early.

## 10. Engineering rules

- TypeScript strict mode, no `any` without a comment explaining why.
- Never commit secrets. All keys go through env vars or Wrangler secrets. Never log secrets, tokens, dumps or personal data.
- Write tests for placement, growth and decay, and the moderation pipeline (plan in `docs/testing.md`).
- Keep AI and moderation calls behind small service modules.
- Seed script with fake plots across a few regions; seed content goes through moderation.
- Keep Worker requests light (10 ms CPU per request on the free plan). Prefer static pages and client-side rendering, and do heavy work in the browser or in cron batches.
- No hard-coded user-facing strings; everything goes through i18n catalogs.
- **Skills and tools:** use the available skills, plugins and MCP servers at the right moment instead of working from memory:
  - design and accessibility skills for screens
  - UX copy for user-facing text
  - code review and security review every phase
  - Playwright for real-browser checks, screenshots and speed budgets
  - a deploy checklist before any deployment

  Don't install anything paid, or anything that needs the owner's credentials, without asking. If a skill that would clearly help isn't installed, say what it is and why. At the end of each phase, list which ones were used.
- When a decision is ambiguous or expensive to undo, ask me instead of guessing.

## 11. Open decisions

- **Region Open Graph images:** proposed free default is the thumbnail of the region's most-visited plot. A dedicated rendered image would need server CPU.
- **Weekly digest channel:** web push and in-app (free). Email would need a paid sender, and Google/GitHub-only sign-in means we don't send email yet.

## 12. Launch checklist (all required before public launch)

**Reminder for the owner: complete every item below before launch.** Dashboards change, so verify each screen when you set it.

**Spending caps and alerts**

| Service | Hard limit | Alert |
| --- | --- | --- |
| Anthropic | Console → Settings → Billing → Spend limits → "Set limit" (monthly). Prepaid credits with auto-reload off also stop at the balance. | Console usage page. Our `ai_spend_daily` cap stops calls at the daily budget. |
| OpenAI (moderation only) | Dedicated project whose key only calls moderation; monthly budget at $0 or minimal in project settings → Limits. | Budget alert email on the same page. |
| Voyage AI | Check the billing dashboard for a hard limit. If none exists, our app enforces a monthly token budget. | Dashboard alerts if offered; our app logs usage against the budget. |
| Cloudflare (Workers Paid, R2) | No hard cap on paid usage, so our per-plot, per-user and daily limits are the cap. | Notifications → billing / usage alerts at low thresholds (for example $1 and $10 over plan). |
| Supabase | Free plan can't overspend. On Pro, keep **Spend Cap** on (default). | Organization → Usage; enable email alerts. |
| PostHog (if used) | Billing limit $0. | Usage alerts. |
| GitHub Actions (CI only) | Billing → Actions spending limit $0. | Usage emails at 75%, 90% and 100%. |

**Safety and legal (get a lawyer's confirmation; this is not legal advice)**

- **Abuse-material hash matching live:**
  - Apply for Microsoft PhotoDNA Cloud Service (free for qualifying services) to match before publishing, wired into `ModerationService`.
  - Also enable Cloudflare's CSAM Scanning Tool (free, scans cached content, blocks matches, emails us) as a second layer after publishing.
- **United States:** 18 U.S.C. § 2258A requires providers to report apparent child sexual abuse material to NCMEC's CyberTipline when they become aware of it, and to preserve the report's contents (currently one year). Cloudflare's tool does not report for us.
  - Register with NCMEC for CyberTipline reporting.
  - Write the internal procedure: who reports, within what time, how evidence is preserved and access-restricted, and that it is never re-shared.
- **India:**
  - IT Act 2000 §67B and the POCSO Act 2012 (§19–20 require reporting to the police or Special Juvenile Police Unit).
  - IT (Intermediary Guidelines and Digital Media Ethics Code) Rules 2021:
    - publish a Grievance Officer
    - acknowledge complaints within 24 hours and resolve them within 15 days
    - remove intimate or sexual content about a person within 24 hours of a complaint
    - act on lawful orders within the required time
  - Report via the National Cyber Crime Reporting Portal (cybercrime.gov.in) as required.
- Terms of service, privacy policy (including analytics and AI processors: Anthropic, OpenAI, Voyage), and a published content policy matching section 3.

**Operations**

- Workers Paid enabled and real CPU per request measured.
- Nightly encrypted backups running, and one restore tested.
- Google and GitHub OAuth apps in production mode.
- Cloudflare Web Analytics on; domain and CDN configured.
- Deploy checklist run.

## 13. Cost notes

Estimates at October 2026 prices; re-check before launch. "Active user" = monthly active, signed-in.

Assumptions per active user per month:
- 8 visits of about 12 minutes
- 4 editing sessions (about 60 saves)
- 4 image uploads (about 120 KB) and 4 thumbnails (about 40 KB); about 2 MB stored per plot
- 6 comments; about 300 app requests
- about 35 moderation checks, 2% of them borderline
- 3 re-embeds of up to 1,000 tokens
- 30% of active users are trust level 0 in a given month; 20% of plots earn growth

A Claude image check costs about $0.00175 on the normal API (a 1,024 px image is about 1,050 tokens, plus the prompt and a short description) and about $0.0009 batched.

| Part | Per 1,000 active users / month | Per 100,000 active users / month |
| --- | --- | --- |
| Cloudflare Workers | $5 (Workers Paid from launch; usage is well inside what's included) | About $12 (about 30M requests and CPU above what's included) |
| Static assets and CDN bandwidth | $0 | $0 |
| R2 storage, writes and cache-miss reads | $0 (inside the free allowance) | About $16 |
| Supabase | $0 (free plan) | $25 (Pro: database over 500 MB, over 50k active users) |
| Voyage (`voyage-4-lite`) | $0 (one-time 200M free tokens) | About $6 |
| OpenAI Moderation | $0 | $0 |
| Claude: image checks, level 0 users (normal API) | About $4 (about 2,400 checks) | About $420 (about 240,000 checks) |
| Claude: image checks, growing and reported plots (batch) | About $1 | About $100 |
| Claude: borderline text (batch) | About $1 | About $60–80 |
| Claude: region and continent names | Under $0.01 | Under $0.10 |
| Auth email | $0 (Google/GitHub only) | $0 |
| Analytics | $0 | $0 (PostHog free tier, if used, has a $0 billing limit) |
| Backups | $0 (inside Workers Paid and R2's free allowance) | Under $1 |
| Domain | About $1 | About $1 |
| **Total** | **About $12–13 a month** | **About $640–660 a month** |

**What we pay for first, in order:**

1. **Workers Paid, $5/month from public launch** (planned).
2. **Anthropic: about $5/month at 1,000 users, growing with new users.** It has no free tier, so it needs prepaid credit from day one.
3. **Supabase Pro, $25/month:** at roughly 15,000–20,000 plots (database size; cold storage pushes this out) or 50,000 active users.

**The biggest lever at scale is Claude's image checks for new users**, about 65% of the 100k-user bill. Ways to cut it:
- promote trustworthy users out of level 0 sooner
- skip the check on thumbnails whose every image has already passed it, checking only their drawings and text
- set the daily cap to the budget we choose; images then wait instead of skipping the check

## 14. Future phase: tile pyramid (triggered by measurement)

With chunked layout JSON and viewport culling, the viewer's cost grows with what is on screen, not with the total number of plots. A pre-rendered tile pyramid becomes worthwhile when one of these holds on our reference device (a mid-range Android phone, Lighthouse mobile emulation with 4× CPU slowdown):

- the zoomed-out view can no longer hold 60fps (95th-percentile frame time over 16.7 ms)
- the layout data needed for the first view exceeds 150 KB gzipped

Rough estimate: **around 250,000 plots**, where per-plot blocks and chunk indexes become too dense at the zoom levels that show them. Phase 2 confirms it with synthetic worlds of 10k, 100k and 1M plots. The tile design (pyramid, dirty-tile rebakes, shared blank tile, takedown handling, compositing that complies with Cloudflare's and GitHub's terms) is kept in `docs/architecture.md` for that phase.

---

Next.js version notes for coding agents: @AGENTS.md
