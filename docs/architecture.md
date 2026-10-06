# Architecture: cheap to look at, pay only for change

Pangaea treats the world like a map service, not a live app. Most visitors only look, so looking
costs almost nothing: static files from a CDN and no database. Expensive work (moderation, AI,
layout builds) runs only when something changes, and only for what changed. `CLAUDE.md` is the
source of truth; this document explains how the pieces fit. The reasons behind each choice are in
`docs/decisions.md`.

## System map

```
Browser ──static JS/CSS (free, unlimited)──► Cloudflare Workers static assets
   │
   ├── layout JSON, thumbnails, snapshots, media ──► Cloudflare CDN ──► R2 (public bucket)
   │
   ├── app pages + small JSON APIs ─────────────► Worker (Next.js via OpenNext)
   │                                                  │
   │                                                  ├─► Supabase Postgres + Auth
   │                                                  ├─► OpenAI Moderation (free)
   │                                                  ├─► Claude Haiku (image checks, borderline, labels)
   │                                                  └─► Voyage (embeddings)
   │
   └── uploads (presigned PUT) ─────────────────► R2 (private bucket)

Cron Triggers ─► same Worker, scheduled handler ─► small batches: moderation queue, Claude
                  batches, embeddings, layout and snapshot builds, link rechecks, cold storage,
                  nightly encrypted backup
```

## The read path: what a visitor costs

| Zoom                  | What loads                                                                                                           | Source   | Database queries |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| World / continents    | `regions` file (vector shapes, colors, labels) and coarse layout chunks                                              | CDN      | 0                |
| Region / neighborhood | Layout chunks in the viewport (plot blocks with ThumbHash), then thumbnails of visible plots                         | CDN      | 0                |
| On a plot             | The plot's published snapshot (approved items as JSON), then media for items on screen, plus HTML overlays for cards | CDN      | 0                |
| Comments              | Paginated query                                                                                                      | Postgres | 1 per page       |

The viewer never loads the editor. Excalidraw is a separate lazy chunk, fetched only when an owner
edits their own plot.

## World viewer (Phase 2)

- **Engine:** PixiJS (WebGL), view only. One camera with momentum pan, pinch zoom and eased
  fly-to. Respects reduced motion: fly-to becomes a quick cross-fade.
- **Layout data.** The world is cut into square chunks of, for example, 64 × 64 grid cells. Each
  chunk file lists its plots as compact arrays: id, x, y, size, region and ThumbHash (about 40
  bytes per plot before gzip).
  - `regions-v<N>.json` holds the simplified region outlines, colors, labels and continent groups.
  - Both are rebuilt by cron in small batches when placement or sizes change, written with
    versioned names, and pointed to by a tiny `world.json` cached for about 60 seconds.
- **Level of detail.**
  - Zoomed out: region fills and outlines with labels, and plot blocks drawn as instanced quads in
    region colors. Blocks fade in only once they are a few pixels wide.
  - Mid zoom: thumbnails for plots in the viewport. ThumbHash shows instantly as a blurred
    placeholder.
  - Textures go through a least-recently-used cache with a memory budget; off-screen textures are
    unloaded.
  - Close zoom: the snapshot, with media loaded only for on-screen items.
- **Card overlays.** When zoomed in on a plot, code and link cards get a real HTML layer positioned
  over the canvas, so code can be selected and copied and links clicked. Overlays exist only for
  cards on screen and above a zoom threshold.
- **Accessibility.**
  - The canvas has a parallel accessible structure: region list view, plot list, and focusable
    plot links in reading order.
  - The command palette and keyboard shortcuts give full non-pointer navigation.

## Editor (Phase 1)

- **Excalidraw (MIT), lazy-loaded.** Our item types are layered on standard elements:
  - **Code card:** an `image` element whose bitmap our code renders (syntax-highlighted, theme-aware).
    `customData = { kind: "code", language, source }`. Double-click opens our dialog; saving the
    dialog re-renders the bitmap.
  - **Link card:** the same pattern, with `customData = { kind: "link", url, title, description,
imageAsset }`. Preview data is fetched by our server and moderated.
  - **Webpage (Phase 6):** an `embeddable` element. `renderEmbeddable` shows the screenshot and a
    "tap to run" button.
- **Mapping to the database.** Each Excalidraw element maps to one `plot_items` row:
  - free-draw strokes and shapes are `drawing`
  - text elements are `text`
  - images are `image`
  - cards are `code` or `link`

  Element version numbers make debounced saves send only changed elements (an upsert by element id,
  plus deletions).

- **Paste and drop.** One detector maps clipboard or drop contents to an item:
  - an image file becomes an image
  - a URL becomes a link card
  - text that looks like code becomes a code card (language detected in the browser with a small
    heuristic and `highlight.js` auto-detect)
  - anything else becomes text

  The same path serves the PWA share target.

- **Offline queue.** Saves go to IndexedDB first, then flush with retry and backoff. With two tabs
  open, the last write to each element wins.
- **Tidy up.** A deterministic shelf-packing layout in the browser: group by type, sort by
  creation time, keep relative order. No server, no AI.
- **Thumbnail.** On save (debounced, and only when the scene changed), `exportToBlob` renders a
  512 px WebP. The upload carries the element ids and versions it was rendered from (see
  "Moderation").

## Uploads (Phase 1)

1. The browser hashes the original file (SHA-256, Web Crypto) and asks the server whether that
   source hash is known. If it is, the existing asset is linked and nothing is uploaded.
2. Otherwise the browser draws the image to a canvas, keeping only the first frame of a GIF. That
   strips the metadata, including GPS location. It then resizes so the longest side is at most
   1,024 px and encodes WebP at quality 0.8 (JPEG if the browser can't encode WebP).
3. The browser asks for a presigned PUT URL. It is for a single-use key unique to this upload
   (`incoming/<user id>/<upload id>`), with the size cap and content type signed in. Keys are never
   shared, so nobody can overwrite another person's file, even one with the same content.
4. On finalize, the server streams the object and verifies its SHA-256 (Web Crypto is native, so
   this is cheap). It checks the image header for type and dimensions, then copies the bytes to
   their content-addressed key `pending/<sha256>` with a server-side copy that clients can't
   write to. It records the asset and queues moderation.
   - Claude checks these exact stored bytes; there is no separate copy that could differ from what
     gets published.
   - If the hash is already known, the incoming object is simply deleted.
5. When approved, the object is copied to the public bucket under `a/<sha256>.webp`. Rejected
   objects are deleted.

## Moderation

Every check is recorded per asset or item, so no hash is ever re-checked for the same purpose.

```
text (items, comments, descriptions, card source)
  └─► OpenAI Moderation ─ clear ─► approve / reject
                        └ borderline ─► Claude (cap) ─ unsure ─► human queue

image / thumbnail
  └─► known approved hash? ─► reuse verdict
  └─► abuse-hash match (PhotoDNA, before launch) ─► block + legal reporting procedure
  └─► OpenAI Moderation (sexual, violence, self-harm)
  └─► Claude check if: uploader is trust 0 (normal API) │ plot starts earning growth (batch) │ reported (batch)
         ├─ also returns a short description ─► assets.ai_description
         └─ cap reached ─► stays pending (never skipped)
```

- **Thumbnails** are published only if they pass image checks and every element id and version they
  were rendered from is approved. Otherwise the previous approved thumbnail stays.
- **Cards:** their source text is moderated. Their bitmap is shown only to the owner in the editor.
  The public sees cards drawn from the moderated source.
- **Trust promotion** (proposed, tunable): level 0 → 1 after 7 days, 5 approved items and no
  rejections in 30 days. Level 1 → 2 after 60 days, 30 approved items, received reports below a
  threshold, and a staff review flag. Faster promotion is the main lever on Claude cost.
- **Reports:** weight = 1.0 for level 2 (blurs immediately), 0.5 for level 1 and 0.25 for level 0.
  The item blurs when the summed weight reaches 1.0. Every report also queues an immediate re-check
  (OpenAI, and Claude for images); a flag blurs the content right away.
- **Abuse-material matching:** PhotoDNA Cloud Service before publishing, and Cloudflare's CSAM
  Scanning Tool on cached content as a second layer. Matches follow the written legal procedure
  (`CLAUDE.md` section 12).

## Placement (Phase 3)

- **Text for embedding:** the description first, then text items, card source and image
  descriptions. Normalized, trimmed to about 2,000 tokens and hashed. If the hash is unchanged,
  nothing happens.
- **Voyage `voyage-4-lite`** at 512 dimensions, stored as `halfvec(512)`, about 1 KB per plot.
  Up to many plots are sent per request.
- **Nearest region** by cosine similarity. Above the threshold the plot is placed by spiral search
  from the region center; below it, the plot goes to the frontier.
- **New regions:** a frontier cluster grows into a new region, which Claude names once (Batch API)
  and which is assigned the next unused color. Continents group regions the same way.
- **Owner choice:** if a plot can't be placed, the owner picks a region from a list. Automatic
  placement then leaves it alone.

## Growth (Phase 4)

```
decaying_time = max(0, now − max(earned_space_updated_at, last_active_at + grace))
earned(now)   = earned_space × 2^(−decaying_time / half_life)
```

- Adding points is a single `UPDATE` that brings `earned_space` up to date and adds the points.
  Owner activity brings it up to date first, then moves `last_active_at`.
- **Gate:** before the first growth applies, every image on the plot must have passed the Claude
  check. Until then, credits accumulate as held credits.
- **Footprints change in steps.** When the next step crossing will happen can be computed, so an
  indexed query finds the plots to update and the layout chunks to rebuild.
- **Attention:** batched beacons every 30 seconds, folded into `attention_daily` with an exact
  per-visitor daily cap. Signed-out visitors only increment the display count.

## Background work (Cron Triggers)

One scheduled handler on the app's Worker dispatches small, time-boxed jobs. Each job claims a few
rows from Postgres with `FOR UPDATE SKIP LOCKED` and stops early when its batch is done.

| Job                    | Interval | Work per run                                           |
| ---------------------- | -------- | ------------------------------------------------------ |
| Moderation queue       | 1 min    | OpenAI checks, Claude normal-API checks within the cap |
| Claude batches         | 5 min    | Submit and collect Message Batches                     |
| Embeddings & placement | 5 min    | Hash-gated, debounced Voyage batch                     |
| Layout & snapshots     | 1 min    | Rebuild only dirty chunks and plots (takedowns first)  |
| Link rechecks          | hourly   | A few dozen links                                      |
| Cold storage           | hourly   | A few dozen idle plots                                 |
| Nightly backup         | daily    | Encrypted dump to R2 (Workers Paid)                    |

The free plan allows 5 cron triggers per account, so jobs share a few schedules and the handler
dispatches by schedule string.

## Hosting and costs

- **Cloudflare Workers via OpenNext.**
  - Static assets are free and unlimited. App requests are 100k/day on Free; Workers Paid costs $5
    and includes 10M requests.
  - CPU per request is 10 ms on Free and up to 30 s on Paid.
  - Measure CPU per route with Workers Observability before launch.
- **R2 + CDN:** no egress fees. Content-addressed objects are cached forever; `world.json` for
  about 60 seconds.
- **Supabase free:** 500 MB database, 50k active users. Cold storage keeps the database small.
- **Backups:**
  - A nightly Cron Trigger streams `COPY … TO STDOUT` per table over a direct Postgres connection
    (`pg` on Workers TCP sockets), gzipped with `CompressionStream`.
  - The data is encrypted with a fresh AES-256-GCM key, wrapped with an RSA-OAEP public key (Web
    Crypto), and uploaded to a private R2 bucket with multipart upload.
  - The private key stays offline with the owner. Nothing about the data, keys or connection
    strings is ever logged.
  - Retention uses R2 lifecycle rules.
  - It needs Workers Paid CPU time (planned for launch). GitHub Actions is not used, because GitHub's
    terms limit hosted runners to building, testing, deploying and publishing the project.

## Future: tile pyramid (triggered by measurement)

Kept for when `CLAUDE.md` section 14's trigger fires:

- **Pyramid:** 512 px WebP tiles. The deepest level composites plot thumbnails; each level above is
  downsampled from its four children.
- **Incremental rebakes:** a changed plot marks only its tiles dirty, and repeat edits collapse into
  one job.
- **Empty areas** share one blank tile.
- **Hash-versioned tile URLs,** with a small manifest per block of tiles.
- **Takedowns** re-render with priority; serious cases are deleted and purged from the CDN.
- **Compositing must run somewhere allowed and cheap:** a Worker on Workers Paid with a WebAssembly
  image library, or a small container if volume demands it. Not GitHub Actions (terms), and not
  other users' browsers (untrusted).
