# Architecture: cheap to look at, pay only for change

Pangaea treats the world like a map service, not a live app. Most visitors only look, so looking
should cost almost nothing: static files from a CDN, no database. The expensive work (rendering,
moderation, AI) runs only when something actually changes, and only for what changed.

This document is the plan. Brief sections it refines are noted inline. Items marked **(Phase N)**
are built in that phase; nothing here changes the phase order.

## The read path: what a visitor costs

| Zoom                | What loads                                                                                  | Source   | DB queries |
| ------------------- | ------------------------------------------------------------------------------------------- | -------- | ---------- |
| World / continents  | Pre-baked map tiles + a small regions file for labels                                       | CDN      | 0          |
| Neighbourhood       | Higher-zoom tiles, which are composited plot thumbnails                                     | CDN      | 0          |
| On a plot           | The plot's published snapshot (approved items as JSON), then media for items on screen only | CDN      | 0          |
| Comments, reactions | Paginated query                                                                             | Postgres | 1 per page |

So panning the whole world, and even opening a plot, never touches the database. The database
serves writes, owners editing their own plot, comments, and the jobs that bake what everyone else
sees.

## Map tiles (Phase 2)

- **Pyramid.** The world grid is cut into 512 px tiles at zoom levels `0..Z`. The deepest level is
  plot thumbnails composited onto the grid. Each level above is built by downsampling its four
  children, so baking never re-renders plot content.
- **Re-render only what changed.** When a plot's thumbnail changes, the tiles it covers are marked
  dirty: about one tile per zoom level, plus a neighbour or two when the plot sits on a tile edge.
  Dirty tiles go into a job queue keyed by tile, so many edits collapse into one rebake.
- **Immutable tile URLs.** A tile's key includes the hash of its image (`t/<z>/<x>/<y>/<hash>.webp`)
  and is cached forever. What changes is a small **manifest** per block of tiles (for example 32×32)
  that lists which tiles exist and their current hashes, cached for about 60 s.
- **Empty space is free.** An empty tile is simply absent from the manifest, so the client draws
  the background colour and makes **no request at all**. That beats a shared blank tile, which would
  still be a request.
- **Labels are drawn by the client** from a small regions file (`regions.json`, about one line per
  region). Text stays sharp at every zoom and a region rename doesn't rebake any tiles.

### Takedowns must beat the cache

Pre-baked images keep showing content after it is removed, unless takedown is designed in:

1. Rejecting or blurring an item triggers a **priority** re-render of the plot thumbnail and its
   tiles. The manifest TTL (about 60 s) bounds how long the old version is reachable through the
   map.
2. For serious content, the old thumbnail and tile objects are **deleted** from storage and **purged
   from the CDN** by URL, because anyone who saved the old URL could still load it.
3. Media is content-addressed (below), so taking down one asset hides it on every plot that uses it.

### Rendering thumbnails without a browser (Phase 2)

The brief asks for server-side PNG thumbnails. Running headless Chromium per save would be the
priciest part of the system. Recommended instead: render a plot's **approved** items to SVG with
our own small renderer (text, strokes, image references, link and code cards), then rasterize to
WebP with `resvg` and `sharp`. It's a few tens of milliseconds of CPU with no browser. At thumbnail
size, small differences from tldraw's own look don't matter.

## Plot snapshots (Phase 1 to 2)

When a plot's approved content changes, the server writes a JSON snapshot of its public items to
`p/<plot id>/<version>.json` in the public bucket. Visitors read that snapshot from the CDN, and
`plots` points at the current version. Snapshots are built only from approved data, the same rule
as `plot_items_public`, which is still the source of truth and covers the owner's own view.

"Load only what's on screen" applies to **media**: a plot's item list is small (one person's
board), so it loads in one go, but images load lazily as they enter the viewport and at the
resolution needed.

## Uploads (Phase 1)

1. The client asks the server for a presigned `PUT` URL for one key under `raw/<user id>/` in the
   private bucket, signed with a size cap. It uploads straight to storage, not through our servers.
2. On finalize, the server hashes the original bytes. If that hash is already in `asset_sources`,
   the existing asset is linked to the user and we're done: **no re-encode, no re-scan**.
3. Otherwise `sharp` decodes the image with a pixel limit (against decompression bombs), fixes
   orientation, keeps only the **first frame** (so moderation sees exactly what will be shown),
   resizes so the longest side is at most 2048 px, **strips metadata** (removing GPS location from
   phone photos) and encodes **WebP**.
4. The output is hashed. That hash is the asset's identity and storage key
   (`pending/<sha256>.webp`). Identical output from different originals also deduplicates.
5. The asset is moderated once. If approved, it is copied to `a/<sha256>.webp` in the public bucket.
   If rejected, the pending copy is deleted. The raw upload is always deleted.

**WebP rather than AVIF for stored media.** AVIF is smaller, but encoding it takes much longer, and
on serverless CPU that's a real cost per upload. WebP decodes everywhere and encodes fast. AVIF can
be added later for tiles, which are encoded once and downloaded many times, if bandwidth data
justifies it.

**Exact hashes don't replace perceptual hashing.** SHA-256 deduplicates byte-identical files. A meme
re-saved by another app is different bytes. Matching known abuse material needs perceptual hashing
(PhotoDNA or similar). That remains the separate, clearly marked hook in `ModerationService` that
the brief asks for.

## Drawings (Phase 1)

- Strokes are simplified (Ramer–Douglas–Peucker at about half a pixel), coordinates are quantized,
  and points are delta-encoded before saving.
- They are stored as compact JSON in `plot_items.content`. Postgres already compresses large values
  (TOAST), so we don't add our own compression on top; base64-encoding compressed bytes would make
  them about a third larger and opaque to the database.
- **Drawings are images to moderation.** Anyone can draw anything, so every drawing is rasterized
  with the thumbnail renderer and sent through image moderation, not just text checks.

## Moderation cost tiers (Phase 1)

Every item still starts `pending` and nothing goes public without a verdict (brief 5.4, no
exceptions). The tiers only change how much a verdict costs:

| Tier | Runs on                         | What                                                                               |
| ---- | ------------------------------- | ---------------------------------------------------------------------------------- |
| 0    | everything, free                | Cached verdict for a known asset hash, URL blocklists, length and rate limits      |
| 1    | everything, cheap               | Text and image classifiers. Clearly safe gets approved, clearly bad gets rejected. |
| 2    | borderline only                 | Claude with vision and the written policy. Gets the context a classifier lacks.    |
| 3    | Tier 2 unsure, reports, appeals | Human review on the admin page                                                     |

The cheap tier may only auto-approve when every score is well clear of the line. Anything else moves
up a tier rather than defaulting to approve.

## AI spend (Phase 3)

- **Change gate.** A summary is regenerated only if a hash of the plot's approved content
  (normalized text plus asset hashes) differs from `plots.summary_source_hash`. Moving items around
  never triggers AI.
- **Debounce.** Summary jobs wait until the plot has been quiet for about 10 minutes. Each edit
  pushes the job back instead of adding another.
- **Model.** `claude-haiku-4-5` by default (`ANTHROPIC_MODEL`), for summaries and region labels.
- **Batch API for non-urgent work.** Re-summaries go through Message Batches at half price. Batches
  usually finish within an hour; the guarantee is 24 hours. A brand-new plot's **first** summary
  runs in real time so new users get placed quickly; until then the plot waits in the frontier.
- **Re-embed only if the summary text changed. Re-place only if** the new embedding has moved away
  from the old one past the threshold (brief 5.1.6).
- Rough cost per summary (about 2,000 tokens in, 150 out): about $0.003 in real time on Haiku,
  about $0.0014 batched. Note that Sonnet 5.5 is only twice Haiku's price, so Sonnet batched costs
  the same as Haiku in real time. **The change gate and the debounce save far more than the model
  choice does.**

## Growth without a growth job (Phase 4)

Refines brief 5.2 ("Recalculate in a scheduled job"). Earned space is stored as a value plus the
time it was last brought up to date (`earned_space`, `earned_space_updated_at`) and computed on read:

```
decaying_time = max(0, now − max(earned_space_updated_at, last_active_at + grace))
earned(now)   = earned_space × 2^(−decaying_time / half_life)
```

- **Adding points** (missions, attention, approved comments) works in one `UPDATE`: set the value to
  `earned(now) + points` and the timestamp to `now`.
- **Owner activity pauses decay** for a grace period. The formula is only exact if earned space is
  brought up to date _before_ `last_active_at` moves, so the activity trigger
  (`private.bump_plot_activity`) must do that once grace exists. This is noted in the trigger.
- **Size changes in steps.** A plot's footprint on the grid changes only at size thresholds, never
  continuously. Otherwise every plot would need a rebake every moment. The moment earned space
  will fall below its current step can be computed ahead of time and stored, and an indexed query
  for "steps that change now" finds the few plots that need a rebake. That touches only the plots
  that changed, never the whole map.

## Attention (Phase 4)

- The browser counts views and visible, focused dwell time per plot and sends them **every
  30 seconds** and when the page is hidden (`sendBeacon`). That's one small request per active
  viewer per 30 seconds, however much they click.
- Client numbers are hints. The server only counts signed-in visitors (open question 5), ignores
  owners visiting their own plot, and caps dwell at the real time elapsed since that visitor's
  last flush.
- Instead of storing raw events, each flush is folded into one `attention_daily` row per plot,
  visitor and day. `credited_score` makes the per-visitor daily cap exact: each flush credits
  `min(cap, score) − credited_score` to the plot's earned space.
- Very popular plots could see contention on their row. If that happens, credits get buffered and
  applied per plot in batches.

## Editing: no real-time servers (Phase 1)

Only the owner edits a plot, so there is no live sync service. The editor saves about 1 to 2 seconds
after the last change, sending only changed items (an upsert by tldraw's stable shape id, which the
schema allows) and deletions, plus a final save when the page is hidden. With two tabs open, the
last write to each item wins.

## Hosting

- **Supabase:** Postgres and Auth. Only writes, owners and comments reach it.
- **Cloudflare R2 + Cloudflare CDN:** all media, thumbnails, tiles, snapshots and manifests. R2
  doesn't charge for data going out. You pay for storage and per operation, and with the CDN in
  front, a read only reaches R2 when the CDN doesn't already have it. Content-addressed keys get
  `Cache-Control: public, max-age=31536000, immutable`, and manifests and `regions.json` get a short
  TTL.
- **Vendor-neutral by design:** the app only speaks the S3 API (`S3_*` env vars). Locally, Supabase
  Storage's S3 endpoint stands in for R2 (`npm run env:local` configures it).
- **Background worker** for thumbnails, tiles, snapshots, moderation escalation and AI batches:
  a Postgres job table (one row per piece of work, so repeat edits collapse; `run_after` for
  debouncing; `SKIP LOCKED` so several workers can share it) drained by a small worker. Where the
  worker runs is an open question.

## Cold storage: deferred

Moving plots nobody has visited in months to cheaper storage doesn't pay yet. A plot's database rows
are kilobytes, and its media already sits in R2, which is the cheap storage. The bills that grow
are bandwidth and compute, which the rest of this document addresses. R2's Infrequent Access tier
also charges per retrieval and has a minimum storage period, so a sleepy plot that gets visited
again costs more, not less. The content-addressed media and snapshots keep the option open:
revisit it when storage shows up as a real line on the bill.

## Live webpages (Phase 6)

Shown as a static screenshot, which is an asset like any other and goes through image moderation,
with a "tap to run" button. The page itself runs only on tap, in the sandboxed iframe on a separate
origin (brief 5.5).
