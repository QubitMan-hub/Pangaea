# Pangaea: Build Brief for Claude Code

Read this whole file before writing any code. It is the source of truth for this project.

## 1. What we are building

Pangaea is "Reddit, but as one giant whiteboard." It is one infinite whiteboard shared by the whole world. Every user gets a small plot on it to share ideas, drawings, images, links, code snippets and (later) live webpages. Claude reads each plot and places it next to plots with related ideas, so the board forms "continents" of topics on its own. Plots grow by completing missions and earning genuine attention, and earned space slowly decays so newcomers can always compete.

Core feeling: a feed makes ideas vanish in a day. Pangaea gives every idea a lasting place on a map you can explore.

## 2. Product rules (do not change without asking)

- One plot per user. Only the owner can edit their plot. Visitors can view, react and comment.
- Space on the public board is never sold. Growth only comes from missions and attention.
- Nothing appears publicly until it passes moderation. No exceptions, including in dev seed data shown to real users.
- Never allowed: nudity or sexual content, gore, hate, harassment, self-harm promotion, scams, malware, illegal content.
- Plots are placed by topic, and placement must be stable. A plot only moves if its content clearly changes topic.
- Earned space decays over time unless the owner stays active.

## 3. Tech stack

Use these unless there is a strong reason not to. If you want to deviate, stop and ask first.

- Frontend: Next.js (App Router) + TypeScript (strict mode) + Tailwind.
- Plot editor: tldraw SDK. Check its current license terms and tell me what they require before we ship anything public.
- World viewer: a custom zoomable map view (canvas/WebGL, PixiJS) that draws pre-baked map tiles when zoomed out, plot thumbnails closer in, and real plot content only when on a plot. See section 9.
- Backend and data: Supabase (Postgres, Auth). Use pgvector for embeddings.
- Object storage and CDN: Cloudflare R2 behind Cloudflare's CDN (free egress), accessed only through the S3 API so the vendor can be swapped. Locally, Supabase Storage's S3 endpoint stands in for it.
- AI: Anthropic API for plot summaries and topic labels. Model name comes from env var `ANTHROPIC_MODEL` (default `claude-haiku-4-5`). Use the Message Batches API for anything not urgent. Embeddings via Voyage AI (`VOYAGE_API_KEY`).
- Moderation: wrap all providers behind one `ModerationService` interface so we can swap vendors. Start with one text and one image moderation API. Leave a clearly marked hook for hash matching against known abuse material (to be added once we are approved for a program like PhotoDNA).
- Thumbnails: render a thumbnail of each plot (server side, from approved content only) when its approved content changes, and store it in object storage.

## 4. Data model (starting point, refine as needed)

- `users`: id, handle, created_at, trust_level (0 new, 1 established, 2 trusted)
- `plots`: id, owner_id, region_id, grid_x, grid_y, base_size, earned_space, last_active_at, summary, embedding, thumbnail_url, status
- `plot_items`: id, plot_id, type (text, drawing, image, link, code, webpage, video, document), content (json), position (json), moderation_status (pending, approved, rejected, blurred), created_at
- `regions`: id, label, centroid_embedding, center_x, center_y, plot_count
- `missions`: id, slug, title, description, reward_points, is_sponsored, starts_at, ends_at
- `mission_completions`: id, mission_id, user_id, plot_id, evidence (json), verified, created_at
- `attention_daily`: plot_id, visitor_id, day, views, dwell_seconds, is_return_visit, credited_score (one row per plot, visitor and day; browser batches are folded in, raw events are not stored)
- `assets`: sha256, mime_type, byte_size, width, height, moderation_status (content-addressed media, stored and moderated once)
- `comments`: id, plot_id, author_id, body, moderation_status, created_at
- `reports`: id, target_type, target_id, reporter_id, reason, status, created_at

Enable Row Level Security everywhere. Only owners can write to their own plot and items.

## 5. Key systems

### 5.1 Placement (Claude organizes the world)

1. When a plot's approved content changes meaningfully, ask Claude for a short topic summary of the plot.
2. Embed the summary with Voyage.
3. Find the nearest region by cosine similarity on `centroid_embedding`.
4. If similarity is above a threshold, place the plot in that region at the nearest free grid cell, spiraling outward from the region center.
5. If no region is close enough, hold the plot in a "frontier" region. When enough similar frontier plots exist, create a new region, ask Claude for a short human-friendly label, and give it space on the map.
6. Re-check placement only when the summary changes a lot (similarity to old summary below a threshold). Never reshuffle the whole map.

### 5.2 Growth and decay

- Plot size = base_size + earned_space.
- Earned space comes from mission points and an attention score.
- Attention score weights dwell time, comments and unique returning visitors far above raw views. Cap how much any single visitor can contribute per day.
- Apply exponential decay to earned space (start with a 30 day half-life, keep it configurable).
- Compute decay on read from the stored value and the time it was last updated. No job crawls all plots. Plot footprints change in steps, and only plots crossing a step are re-rendered.
- Changing a plot's size must never overlap neighbors. Reserve growth room around plots or push neighbors outward within the region. Pick an approach, explain it, and keep it simple.

### 5.3 Missions (MVP set)

1. Leave thoughtful comments on three neighboring plots.
2. Answer a question someone pinned on their plot.
3. Visit a region you have never visited and leave a note.
4. Complete your plot with at least three items.

Verify completions automatically where possible. Low-effort comments should not count (use a simple quality check).

### 5.4 Moderation pipeline

1. Every new item and comment starts as `pending` and is invisible to everyone except its owner.
2. Run it through `ModerationService`. Approved items go public. Rejected items stay private with a clear reason shown to the owner.
3. Trust levels: level 0 users can post text, drawings, images, links and code. Webpages and video unlock at level 1.
4. Reports immediately blur the content for viewers while it is reviewed.
5. Build a minimal admin page to review reports, borderline items and appeals.
6. Links: store them, show preview cards, and recheck destinations on a schedule.

### 5.5 Live webpages (Phase 2 only)

- Serve user HTML from a separate origin, inside iframes with the `sandbox` attribute and a strict Content Security Policy.
- No access to the parent page, cookies or visitor data. No pop-ups, no top-level navigation.
- Size limits per plot. Get a security review checklist written before enabling this publicly.

## 6. Build phases

Work one phase at a time. At the end of each phase: run the tests, summarize what was built, list anything you were unsure about, and stop for my review before starting the next phase.

**Phase 0: Setup.** Repo structure, Next.js app, Supabase project schema and migrations, env var template (`.env.example`), lint, formatting, test setup, and a README explaining how to run it locally.

**Phase 1: Plots.** Auth, plot creation on signup, a plot editor built on tldraw supporting text, drawings, images, links and code cards. Items saved to the database. Moderation pipeline wired in from day one.

**Phase 2: The world map.** Pre-baked map tiles with incremental rebakes, zoomable world viewer with plot thumbnails on a grid, region labels when zoomed out, click to open a plot, a "wander" button that jumps to a random plot in an unvisited region.

**Phase 3: Claude placement.** Summaries, embeddings, region assignment, frontier region, new region creation, stable placement rules.

**Phase 4: Growth.** Batched attention tracking, missions, growth and decay computed on read, plot resizing without overlaps.

**Phase 5: Safety and polish.** Reports, blur on report, admin review page, trust levels, rate limits, link rechecks.

**Phase 6 (later):** Live webpages in sandboxed iframes, video, private islands for schools and events, plot cosmetics.

## 7. Not in the MVP

Real-time multi-user editing, plot merging, payments, mobile apps, private islands, video, live webpages. Do not build these early.

## 8. Engineering rules

- TypeScript strict mode, no `any` without a comment explaining why.
- Never commit secrets. All keys go through env vars.
- Write tests for placement, growth and decay, and the moderation pipeline. These are the parts that must not break silently.
- Keep AI calls behind small service modules so prompts and providers are easy to change.
- Seed script with fake plots across a few regions so the map can be tested without real users. Seed content must also pass through moderation.
- When a decision is ambiguous or expensive to undo, ask me instead of guessing.

## 9. Efficiency: looking is cheap, change is what costs

Most visitors only look. Looking should cost almost nothing, and expensive work should run only when something actually changes. Details and reasoning: `docs/architecture.md`.

- The world is a stack of pre-baked image tiles served from a CDN. Browsing never touches the database. When a plot changes, re-render only the tiles it sits on. Empty space costs nothing.
- Load detail by zoom: tiles, then thumbnails, then real content. Load media only for items on screen.
- Shrink every byte: re-encode uploads (WebP, resized, metadata stripped). Store drawings as simplified stroke data. Content-address files by hash so each is stored and moderated once.
- Spend AI only on real changes: content-hash gate and debounce before any summary, a cheap model, and the Batch API when not urgent. Moderation runs a cheap first pass on everything and escalates only borderline cases. The "nothing public before moderation" rule still has no exceptions.
- No scheduled jobs crawling every plot. Do the math on read. The browser batches attention (about every 30 s).
- No real-time sync servers. Owners' edits are saved debounced to the normal database.
- Live webpages show as a static screenshot with "tap to run" (Phase 6).

---

Next.js version notes for coding agents: @AGENTS.md
