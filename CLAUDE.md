# Pangaea: Build Brief for Claude Code

Read this whole file before writing any code. It is the source of truth for this project. Where `docs/` disagrees with this file, this file wins.

## 1. What we are building

Pangaea is "Reddit, but as one giant whiteboard." It is one infinite whiteboard shared by the whole world. Every user gets a small plot on it to share ideas, drawings, images, links, code snippets and (later) live webpages. Pangaea reads each plot and places it next to plots with related ideas, so the board forms "continents" of topics on its own. Plots grow by completing missions and earning genuine attention, and earned space slowly decays so newcomers can always compete.

Core feeling: a feed makes ideas vanish in a day. Pangaea gives every idea a lasting place on a map you can explore.

## 2. Top priority: lowest possible running cost

Running cost is the most important constraint on this project right now.

- For every technical decision, pick the cheapest option that works reliably.
- Stay inside free tiers for as long as possible.
- **If a choice would add recurring cost, stop and tell me the cost and the free alternative before doing it.**
- Most visitors only look. Looking must cost almost nothing (static files from a CDN, no database). Expensive work runs only when something actually changes, and only for what changed.

### 2.1 Cost rules (hard requirements)

1. **Map tiles.** Render the world as a pyramid of image tiles at several zoom levels. When a plot changes, re-render only the tiles it touches. Empty areas share one blank tile.
2. **Level of detail.** Zoomed out: tiles. Mid zoom: plot thumbnails. Zoomed in close: full content, only for plots on screen. Live webpages show a static screenshot with a "tap to run" button and load only when tapped.
3. **Thumbnails** are rendered in the owner's browser when they save, then uploaded. We pay no server compute for them. A thumbnail goes through moderation like any other image (see 6.4).
4. **Uploads.** Compress and resize images in the browser before upload (AVIF, with WebP fallback, and JPEG only for browsers that can encode neither). Strip metadata. Hash every file and store duplicates once. Store drawings as simplified, compressed stroke data.
5. **Per-plot limits.** Cap total storage and the number of items per plot, so no single user can run up the storage bill (defaults in 6.5).
6. **Placement.** Embed each plot's text directly with Voyage (free tier). No separate Claude summary step for now. Claude only names new regions: once per region, label cached forever. Model `claude-haiku-4-5-20251001` from env var `ANTHROPIC_MODEL`. Use the Message Batches API for anything not urgent.
7. **Re-embed only on meaningful change** to a plot's text.
8. **Never rescan a file whose hash was already approved.**
9. **Growth and decay.** No scheduled job over all plots. Store `earned_space` with a last-updated timestamp and compute decay at read time with a closed-form formula.
10. **Attention.** The browser batches views and dwell time and sends them roughly every 30 seconds.
11. **No real-time sync servers.** Only owners edit their plots, so saves are debounced.
12. **Cold storage.** A plot with no visits for 90 days moves its full content to cheaper storage (R2). Its thumbnail stays on the map. It comes back automatically when its owner edits it.
13. **Spending caps.** Every paid or metered service has a hard monthly limit and a usage alert, set before launch (section 11).

## 3. Product rules (do not change without asking)

- One plot per user. Only the owner can edit their plot. Visitors can view, react and comment.
- Users pick their handle at signup.
- Space on the public board is never sold. Growth only comes from missions and attention.
- Nothing appears publicly until it passes moderation. No exceptions, including in dev seed data shown to real users.
- Never allowed: nudity or sexual content, gore, hate, harassment, self-harm promotion, scams, malware, illegal content.
- Plots are placed by topic, and placement must be stable. A plot only moves if its content clearly changes topic.
- Earned space decays over time unless the owner stays active.
- Plot owners can delete comments on their own plot. Deleted comments disappear for everyone else but stay stored for moderators.
- Signed-out visitors' views count for display only. Only signed-in visitors contribute to growth.

## 4. Tech stack

Use these unless there is a strong reason not to. If you want to deviate, stop and ask first.

- **App:** Next.js (App Router) + TypeScript (strict mode) + Tailwind, hosted on **Cloudflare Workers via OpenNext** (`@opennextjs/cloudflare`), free plan. Not Vercel: Vercel's free plan doesn't allow commercial use. If Next.js on Cloudflare causes real problems, tell me before switching.
- **Plot editor:** **Excalidraw** (MIT license). tldraw is not used anywhere. Our own item types on top of Excalidraw: code cards with syntax highlighting, link preview cards, and later sandboxed webpages. If Excalidraw can't support something we need, tell me instead of working around it silently.
- **World viewer:** our own, built with **PixiJS** (WebGL). View only. It must never load the editor, or full plot contents, when zoomed out.
- **Database and auth:** **Supabase**, free plan. Postgres with pgvector.
- **Object storage and CDN:** **Cloudflare R2** behind Cloudflare's CDN (no egress fees) for images, thumbnails, map tiles, plot snapshots and cold storage. The app talks to it only through the S3 API. Locally, Supabase Storage's S3 endpoint stands in for it.
- **Background work:** **Cloudflare Cron Triggers** calling our routes, each run processing a small batch. Move to an always-on container only when volume justifies it, and ask me first.
- **Embeddings:** Voyage AI, `voyage-4-lite` (env `VOYAGE_MODEL`), 512 dimensions stored as `halfvec(512)` to stay small inside the free 500 MB database. Voyage 4-series embeddings are mutually compatible, so we can upgrade the model later without re-embedding everything.
- **AI:** Anthropic API, `claude-haiku-4-5-20251001` (env `ANTHROPIC_MODEL`). Used only for naming new regions and for borderline moderation cases. Batch API for anything not urgent.
- **Moderation:** **OpenAI Moderation API** (`omni-moderation-latest`, free) as the single provider for text and images, behind one `ModerationService` interface so we can switch later. Claude (Haiku) reviews only borderline cases, under a daily spend cap. Humans handle what Claude can't decide. Keep a clearly marked hook for hash matching against known abuse material (PhotoDNA or similar, once approved for such a program).
- **Placeholders:** until the Cloudflare account and domain exist, use placeholder env vars. The owner sets those up before deployment.

## 5. Data model (starting point, refine as needed)

- `users`: id, handle (picked at signup), created_at, trust_level (0 new, 1 established, 2 trusted)
- `plots`: id, owner_id, region_id, grid_x, grid_y, base_size, earned_space, earned_space_updated_at, last_active_at, last_visited_at, text_hash (hash of the text last embedded), embedding halfvec(512), thumbnail asset, snapshot version, cold_storage_key (set while in cold storage), display_view_count, status
- `plot_items`: id, plot_id, type (text, drawing, image, link, code, webpage, video, document), content (json), position (json), asset_sha256, moderation_status (pending, approved, rejected, blurred), created_at
- `assets`: sha256, mime_type, byte_size, width, height, moderation_status (content-addressed: stored and moderated once)
- `regions`: id, label (named once by Claude, then cached forever), centroid_embedding, center_x, center_y, plot_count
- `missions`: id, slug, title, description, reward_points, is_sponsored, starts_at, ends_at
- `mission_completions`: id, mission_id, user_id, plot_id, evidence (json), verified, created_at
- `attention_daily`: plot_id, visitor_id, day, views, dwell_seconds, is_return_visit, credited_score (one row per plot, signed-in visitor and day; batches are folded in, raw events are not stored; rows older than about 35 days are deleted)
- `comments`: id, plot_id, author_id, body, moderation_status, deleted_at, deleted_by, created_at
- `reports`: id, target_type, target_id, reporter_id, reporter_trust_level, weight, reason, status, created_at
- `ai_spend_daily`: day, purpose, tokens, estimated_cost (enforces the daily Claude cap)

Enable Row Level Security everywhere. Only owners can write to their own plot and items.

## 6. Key systems

### 6.1 Placement

1. When a plot's approved text changes meaningfully (6.8), embed the text directly with Voyage. Embed at most the first ~2,000 tokens.
2. Find the nearest region by cosine similarity on `centroid_embedding`.
3. If similarity is above a threshold, place the plot in that region at the nearest free grid cell, spiraling outward from the region center.
4. If no region is close enough, hold the plot in the "frontier" region. When enough similar frontier plots exist, create a new region and ask Claude (Batch API) for a short human-friendly label. Cache that label forever and never ask again for that region.
5. Re-check placement only when the new embedding is far from the old one. Never reshuffle the whole map.
6. Plots with no text (only drawings or images) can't be embedded and stay in the frontier. See open decision D5.

### 6.2 Growth and decay

- Plot size = base_size + earned_space.
- Earned space comes from mission points and an attention score from signed-in visitors.
- Attention score weights dwell time, comments and unique returning visitors far above raw views. Cap how much any single visitor can contribute per day.
- Exponential decay with a 30 day half-life (configurable), computed on read:
  `earned(now) = earned_space × 2^(−max(0, now − max(earned_space_updated_at, last_active_at + grace)) / half_life)`.
  Adding points sets `earned_space = earned(now) + points` and the timestamp to now. Owner activity brings earned space up to date before moving `last_active_at`.
- Footprints change in steps, never continuously. Only plots crossing a step are re-rendered, and those are found with an indexed query.
- Changing a plot's size must never overlap neighbors. Reserve growth room around plots or push neighbors outward within the region. Pick an approach, explain it, and keep it simple.

### 6.3 Missions (MVP set)

1. Leave thoughtful comments on three neighboring plots.
2. Answer a question someone pinned on their plot.
3. Visit a region you have never visited and leave a note.
4. Complete your plot with at least three items.

Verify completions automatically where possible. Low-effort comments should not count (use a simple quality check).

### 6.4 Moderation pipeline

1. Every new item, comment, image and thumbnail starts as `pending` and is invisible to everyone except its owner.
2. Checks, cheapest first:
   - A file whose hash was already approved is never rescanned.
   - OpenAI Moderation on everything: text, images and thumbnails.
   - Borderline results go to Claude (Haiku), within the daily spend cap. When the cap is reached, borderline cases wait for the next day or for a human.
   - Whatever Claude can't decide goes to humans on the admin page.
3. Approved content goes public. Rejected content stays private with a clear reason shown to the owner.
4. **Thumbnails** are rendered in the browser, so they are untrusted. A thumbnail is published only if it passes image moderation **and** every item in the scene it was rendered from is already approved. The server checks the item versions sent with the upload.
5. **Trust levels:** level 0 users can post text, drawings, images, links and code. Webpages and video unlock at level 1.
6. **Reports are weighted by trust.** A report from a trusted user (level 2) blurs the content immediately. Reports from newer users add up toward a threshold that blurs it. Every report also triggers an immediate automated re-check, and if that check flags the content, it is blurred right away regardless of who reported it.
7. A minimal admin page reviews reports, borderline items and appeals.
8. Links: store them, show preview cards, and recheck destinations on a schedule (small cron batches).

### 6.5 Uploads, media and limits

- The browser resizes images (longest side at most 1,600 px), re-encodes them (AVIF, WebP fallback, JPEG last resort) and strips metadata. Re-encoding through a canvas drops metadata. GIFs keep only their first frame.
- The browser hashes the original file. If that hash maps to an existing asset, nothing is uploaded. Otherwise it uploads the encoded file to a presigned URL with a signed size cap, and the server verifies the file's hash before recording it.
- Content-addressed keys in R2. Approved media is served from the public bucket with immutable caching.
- Drawings: strokes simplified (Ramer–Douglas–Peucker), coordinates quantized and delta-encoded, stored compactly.
- Default per-plot limits (configurable): 10 MB of stored media including the thumbnail, 30 images, 2,000 drawing elements, 1 MB of scene data. Default per-user limit: 30 uploads a day.

### 6.6 Map and viewer

- Tile pyramid of 512 px WebP tiles. The deepest level is plot thumbnails composited onto the grid; each level above is downsampled from its four children.
- A plot change marks only the tiles it touches as dirty. Repeat edits to a tile collapse into one rebake.
- Empty areas use one shared blank tile.
- Tiles and thumbnails use hash-versioned, immutable URLs. A small manifest per block of tiles (short cache) points at the current versions.
- **Takedowns:** rejecting or blurring content triggers a priority re-render of the affected thumbnail and tiles. For serious content, the old objects are also deleted and purged from the CDN.
- Region labels are drawn by the viewer from a small regions file, not baked into tiles.
- Close up, the viewer loads a plot's published snapshot (approved items as JSON) from the CDN, and media only for items on screen.
- **Where tile compositing runs is not decided yet** (open decision D1).

### 6.7 Editing and saving

- Excalidraw scene, saved debounced (about 1 to 2 seconds after the last change), sending only changed elements, plus a final save when the page is hidden.
- No live sync. With two tabs open, the last write to each element wins.

### 6.8 AI and embedding spend

- **Meaningful change:** normalize the plot's approved text and hash it. If the hash equals `text_hash`, do nothing. Otherwise wait until the plot has been quiet for about 10 minutes, then re-embed.
- Embeddings are batched: many plots per Voyage request.
- Claude is called only for new region names and borderline moderation. Both go through the Batch API unless urgent, and both count against `ai_spend_daily`.

### 6.9 Attention

- The browser counts views and visible, focused dwell time while a plot is open, and sends them about every 30 seconds and when the page is hidden (`sendBeacon`).
- The server ignores owners viewing their own plot, caps dwell at the real time since that visitor's last report, and folds each batch into `attention_daily`. Each report credits `min(daily cap, score) − credited_score` to earned space.
- Signed-out visitors only increment the display view count, batched and at most once per plot per visit.
- Updates `last_visited_at` at most once per plot per day (used by cold storage).

### 6.10 Cold storage

- A Cron Trigger finds plots with `last_visited_at` older than 90 days through an indexed query, in small batches. It writes their full content to R2 (standard storage class, not Infrequent Access, which has retrieval fees and a 30 day minimum) and removes the content rows from Postgres. That keeps the database inside the free 500 MB.
- The thumbnail, tiles and published snapshot stay, so the plot still looks the same on the map.
- An owner edit, or a visitor opening the plot, restores it.

### 6.11 Live webpages (Phase 6 only)

- Shown as a static screenshot (an asset, moderated like any image) with a "tap to run" button.
- On tap: serve the user's HTML from a separate origin, inside an iframe with the `sandbox` attribute and a strict Content Security Policy.
- No access to the parent page, cookies or visitor data. No pop-ups, no top-level navigation.
- Size limits per plot. Get a security review checklist written before enabling this publicly.

## 7. Build phases

Work one phase at a time. At the end of each phase: run the tests, summarize what was built, list anything you were unsure about, and stop for my review before starting the next phase.

**Phase 0: Setup.** Repo structure, Next.js app on Cloudflare via OpenNext, Supabase schema and migrations, env var template (`.env.example`), lint, formatting, test setup, and a README explaining how to run it locally. (Built. It needs a rework for this version of the brief: schema changes, Cloudflare config, docs.)

**Phase 1: Plots.** Auth with handle picked at signup, plot creation on signup, an Excalidraw-based plot editor supporting text, drawings, images, links and code cards. Debounced saves, browser-side image processing and thumbnails, per-plot limits. Moderation pipeline wired in from day one.

**Phase 2: The world map.** Tile pyramid with incremental rebakes, PixiJS world viewer (tiles, then thumbnails, then snapshots), region labels when zoomed out, click to open a plot, a "wander" button that jumps to a random plot in an unvisited region.

**Phase 3: Placement.** Text embeddings with Voyage, region assignment, frontier region, new regions named once by Claude, stable placement rules.

**Phase 4: Growth.** Batched attention tracking, missions, growth and decay computed on read, plot resizing without overlaps, cold storage.

**Phase 5: Safety and polish.** Trust-weighted reports with automated re-checks, blur on report, admin review page, trust levels, rate limits, link rechecks, owner comment deletion.

**Phase 6 (later):** Live webpages (screenshot plus sandboxed iframe), video, private islands for schools and events, plot cosmetics.

## 8. Not in the MVP

Real-time multi-user editing, plot merging, payments, mobile apps, private islands, video, live webpages. Do not build these early.

## 9. Engineering rules

- TypeScript strict mode, no `any` without a comment explaining why.
- Never commit secrets. All keys go through env vars.
- Write tests for placement, growth and decay, and the moderation pipeline. These are the parts that must not break silently.
- Keep AI and moderation calls behind small service modules so prompts and providers are easy to change.
- Seed script with fake plots across a few regions so the map can be tested without real users. Seed content must also pass through moderation.
- Keep Worker requests light: on the free plan each request gets 10 ms of CPU. Prefer static pages and client-side rendering; do heavy work in the browser or in cron batches.
- When a decision is ambiguous or expensive to undo, ask me instead of guessing.

## 10. Open decisions (ask before building these)

- **D1. Where map tiles are composited.** A Worker on the free plan has only 10 ms of CPU, which is far too little for image work. Options:
  - **(a)** A GitHub Actions workflow, triggered only when tiles are dirty, using `sharp`. Free: about 2,000 minutes a month for a private repo.
  - **(b)** The owner's browser composites the tiles it touches at save time. Free, but neighbours' tiles become untrusted input.
  - **(c)** Workers Paid at $5/month, with a WebAssembly image library.

  Recommended: (a).
- **D2. Excalidraw has no API for custom element types**, and `exportToBlob` renders embeddable elements as a text placeholder. Proposed:
  - Code cards and link cards are standard Excalidraw image elements that our code renders (syntax-highlighted card, preview card). Their source is in the element's `customData` and they are edited through our own dialog. This way they move, resize and appear in thumbnails like any image.
  - Live webpages (Phase 6) use an embeddable element with `renderEmbeddable` showing the screenshot and the "tap to run" button.
- **D3. OpenAI's image moderation covers only sexual, violence and self-harm categories.** Hate, harassment, illicit content and sexual content involving minors are text-only and score 0 for images.
  - Because all sexual content is banned here, the image "sexual" category still blocks sexualized images of minors.
  - Hate symbols and hateful text inside images go unchecked unless something else catches them.
  - Options: rely on reports and trust; send images from level 0 users to Claude within the daily cap; or send all images to Claude, which costs about $0.001 per image batched.
- **D4. AVIF in the browser.** Browsers can't encode AVIF through a canvas. It needs a WebAssembly encoder (about 1 MB or more, loaded only when uploading), and it is slow on phones. WebP is native in most browsers.
- **D5. Plots with no text** can't be embedded and would sit in the frontier forever. Proposed free fix: ask owners for a one-line plot description at signup, and embed that too.
- **D6. Auth emails.** Supabase's built-in email is only for testing. Free options: sign-in with Google or GitHub only (no email cost), or a free SMTP tier (about 3,000 emails a month) for email sign-in.
- **D7. Backups.** Supabase's free plan has no backups. Proposed free fix: a nightly `pg_dump` from GitHub Actions to R2.

## 11. Spending caps and alerts (set all of these before launch)

**Reminder for the owner: set every item below before launch.** Dashboards change, so verify each screen when you set it.

| Service | Hard limit | Alert |
| --- | --- | --- |
| Anthropic | Console → Settings → Billing → Spend limits → "Set limit" (monthly). Prepaid credits with auto-reload off also stop spending at the balance. | Console usage page. Our own `ai_spend_daily` cap stops calls at the daily budget. |
| OpenAI (moderation only) | Free endpoint. Use a dedicated project whose key can only call moderation, with a $0 or minimal monthly budget in project settings → Limits. | Budget alert email in the same Limits page. |
| Voyage AI | Check the billing dashboard for a hard limit. If none exists, our app enforces a monthly token budget. | Billing dashboard alerts if offered; our app logs usage against the budget. |
| Cloudflare (Workers, R2) | Workers Free has hard daily limits (requests fail, nothing is billed). R2 needs a card and has **no hard cap**, so our per-plot and per-user limits are the cap. On Workers Paid there is no hard cap either. | Notifications → billing / usage-based billing alerts at low thresholds (for example $1 and $5). |
| Supabase | Free plan cannot overspend; the project is restricted at limits. On Pro, keep **Spend Cap** on (default). | Organization → Usage; enable email alerts. |
| GitHub Actions | Billing → Spending limit for Actions: $0. | Usage emails at 75%, 90% and 100% of free minutes. |

## 12. Cost notes

Estimates, October 2026 prices, to be re-checked before launch. "Active user" = monthly active, signed-in.

Assumptions per active user per month: 8 visits of about 12 minutes; 4 editing sessions (about 60 debounced saves); 4 image uploads (about 120 KB each after compression) and 4 thumbnails (about 40 KB); about 2 MB stored per plot on average; 6 comments; about 300 app requests (most of them attention batches); about 35 moderation checks, 2% of them borderline; 3 re-embeds of up to 1,000 tokens.

| Part | Per 1,000 active users / month | Per 100,000 active users / month |
| --- | --- | --- |
| Cloudflare Workers (app, API, cron) | $0. About 300k requests, roughly 10k a day, under the 100k/day free limit. | About $12. Workers Paid $5, including 10M requests; about 30M requests, so +$6 in requests and about +$1 in CPU. |
| Static assets and CDN bandwidth | $0. Static asset requests are free and unlimited; no egress fees. | $0 |
| Cloudflare R2 storage (about 2 MB per plot plus tiles) | $0 (about 2 GB, free up to 10 GB) | About $3 (about 220 GB at $0.015/GB-month) |
| R2 writes (uploads, thumbnails, tiles, snapshots) | $0 (about 40k, free up to 1M) | About $14 (about 4M at $4.50 per million after the free 1M) |
| R2 reads that miss the CDN cache | $0 | About $1 |
| Supabase (Postgres, Auth) | $0. About 25 MB of data, well under 500 MB. | $25. Pro plan, needed for database size (over 500 MB) and active users (over 50k). Covers 8 GB and 100k active users. |
| Voyage embeddings (`voyage-4-lite`) | $0. About 3M tokens a month, inside the one-time 200M free tokens. | About $6. About 300M tokens a month; the free 200M is used up in the first month, then $0.02 per million. |
| OpenAI Moderation | $0 (free endpoint) | $0, within rate limits |
| Claude: region names | Under $0.01 | Under $0.10 |
| Claude: borderline moderation (Batch API) | About $1 | About $60 to $80. The daily cap holds it; overflow waits for humans. |
| Auth email | $0 with Google/GitHub sign-in | $0 with Google/GitHub sign-in (email sign-in at this scale is about $20/month) |
| GitHub Actions (CI, tiles if D1(a), backups) | $0 | $0 to a few dollars, depending on tile volume |
| Domain | About $1 (about $10–15 a year) | About $1 |
| **Total** | **About $1–2 a month**, plus $5 if Workers Paid is needed early | **About $120–140 a month** |

**The first services we would pay for:**

1. **Anthropic, from day one,** but only cents. It has no free tier, so it needs a small prepaid credit, which lasts months at this scale.
2. **Cloudflare Workers Paid ($5/month) is the first recurring bill.** It's needed when daily requests pass 100k (a few thousand active users at these assumptions), or earlier if Next.js pages regularly exceed the free plan's 10 ms CPU per request.
3. **Supabase Pro ($25/month) is the first big step.** Without cold storage, the free 500 MB database fills at roughly 15,000 to 20,000 plots, or the 50k active-user limit is reached first. Cold storage and keeping media out of Postgres push this point out.

The biggest variable cost at scale is Claude's borderline moderation. The daily cap is the control.

---

Next.js version notes for coding agents: @AGENTS.md
