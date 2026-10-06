# Architecture decision records

Each record has its context, the decision, its consequences and the alternatives considered.
`CLAUDE.md` is the source of truth; these records explain why. A new decision gets a new record,
and a changed decision is marked **Superseded** with a pointer to the record that replaced it.

| #   | Decision                                                           | Status   |
| --- | ------------------------------------------------------------------ | -------- |
| 001 | Cost is the top constraint                                         | Accepted |
| 002 | Next.js on Cloudflare Workers via OpenNext; Workers Paid at launch | Accepted |
| 003 | Supabase free plan; safety rules enforced in the database          | Accepted |
| 004 | Cloudflare R2 behind the CDN, S3 API only, content-addressed media | Accepted |
| 005 | Excalidraw editor; cards as image elements with HTML overlays      | Accepted |
| 006 | Vector map layout and viewport thumbnails; tile pyramid deferred   | Accepted |
| 007 | Image processing and thumbnails in the browser; WebP only          | Accepted |
| 008 | Moderation: OpenAI first, Claude image checks, caps never bypass   | Accepted |
| 009 | Placement from direct embeddings; required plot descriptions       | Accepted |
| 010 | Growth computed on read; attention batched                         | Accepted |
| 011 | Background work on Cron Triggers; GitHub Actions for CI only       | Accepted |
| 012 | Nightly encrypted backups from a Worker cron                       | Accepted |
| 013 | Google and GitHub sign-in only                                     | Accepted |
| 014 | Cold storage in R2 after 90 days without visits                    | Accepted |
| 015 | Reports weighted by trust, with automatic re-checks                | Accepted |
| 016 | Comment deletion is soft; owners can delete on their plot          | Accepted |
| 017 | i18n with next-intl; cookieless analytics                          | Accepted |
| 018 | Abuse-material hash matching required before launch                | Accepted |

---

## ADR-001: Cost is the top constraint

- **Context:** Pangaea is pre-revenue and image-heavy. Egress, compute and AI are the costs that
  grow with users.
- **Decision:**
  - Pick the cheapest option that works reliably, and stay on free tiers through development.
  - Any recurring cost is flagged to the owner, together with the free alternative, before it is
    added.
  - Looking costs nothing (CDN and static files); work runs only on change.
- **Consequences:** more work happens in the browser and in cron batches. Some features wait until
  measurement justifies them (ADR-006). Speed and UX still have hard budgets (`docs/design.md`).

## ADR-002: Next.js on Cloudflare Workers via OpenNext; Workers Paid at launch

- **Context:** Vercel's free plan forbids commercial use. On Cloudflare, static assets are free and
  unlimited and there's no egress fee, but the free plan allows only 10 ms of CPU and 100k requests
  a day.
- **Decision:**
  - Run Next.js on Workers with `@opennextjs/cloudflare`. Develop on Free; plan Workers Paid
    ($5/month) for public launch.
  - Keep requests light, prefer static and client rendering, and measure CPU per route with Workers
    Observability.
- **Consequences:** Next.js features OpenNext doesn't support (Node middleware) are avoided. Cron
  Triggers share the same Worker (ADR-011).
- **Alternatives:**
  - Vercel: commercial-use restriction.
  - A plain single-page app on Cloudflare Pages: loses server components and the API surface we
    need.
  - A VPS: a fixed cost and operations work.

## ADR-003: Supabase free plan; safety rules enforced in the database

- **Context:** we need Postgres, auth and vector search for free, and safety rules that a bug or a
  hand-crafted request can't bypass.
- **Decision:**
  - Supabase free plan.
  - Row Level Security on every table, with privileges granted explicitly per table and column.
  - Guard triggers force content to `pending` on create and edit.
  - The public reads approved content only through views.
  - Privileged helpers live in a `private` schema the API doesn't expose.
- **Consequences:** the database is the last line of defense; the pgTAP tests cover it. The free
  plan's 500 MB is the first wall (cold storage, 512-dimension half-precision vectors, media in R2).
  Supabase's advisor flags the public views (intentional, commented).

## ADR-004: Cloudflare R2 behind the CDN, S3 API only, content-addressed media

- **Context:** egress fees are the main cost of an image-heavy map.
- **Decision:**
  - R2 has no egress fees. Public objects are served through a Cloudflare custom domain with
    immutable caching.
  - The app speaks only the S3 API, so the vendor can be swapped; locally, Supabase Storage stands
    in.
  - Media is keyed by SHA-256, stored once and moderated once.
- **Consequences:** R2 has no hard spending cap, so our per-plot and per-user limits are the cap.
  The R2 class used is Standard: Infrequent Access has retrieval fees and a 30-day minimum.

## ADR-005: Excalidraw editor; cards as image elements with HTML overlays

- **Context:** tldraw needs a paid license for commercial production use; Excalidraw is MIT.
  Excalidraw has no API for custom element types, and its `exportToBlob` renders embeddable elements
  as a text placeholder.
- **Decision:**
  - Code and link cards are standard image elements that our code renders, with their source in
    `customData` and edited through our dialog.
  - In the public viewer, real HTML is overlaid on cards when zoomed in, so code can be copied and
    links clicked.
  - The card's source text is what gets moderated.
  - Webpages (Phase 6) use an embeddable element with a custom renderer.
- **Consequences:** cards move, resize and appear in thumbnails like any image. The public never sees
  the browser-rendered card bitmap on its own; cards are drawn from moderated source. The editor is a
  lazy chunk, never loaded by the viewer.
- **Alternatives:** keep tldraw (license cost); fork Excalidraw (maintenance burden).

## ADR-006: Vector map layout and viewport thumbnails; tile pyramid deferred

- **Context:** a tile pyramid needs image compositing on a server, and nowhere free and allowed can
  run it yet: a free Worker has 10 ms of CPU, GitHub's terms rule out Actions, and other users'
  browsers aren't trusted.
- **Decision:**
  - Zoomed out: regions as vector shapes with labels and plots as blocks, from small cached layout
    JSON chunks.
  - Mid zoom: thumbnails only for the viewport, through a texture cache that unloads off-screen
    textures.
  - Close zoom: full content.
  - The tile pyramid becomes a future phase, triggered by measurement (`CLAUDE.md` section 14,
    estimated at around 250k plots).
- **Consequences:** no server image work at all. Vector rendering stays sharp at every zoom and is
  beautiful by design (`docs/design.md`).

## ADR-007: Image processing and thumbnails in the browser; WebP only

- **Context:** server-side image processing costs CPU. AVIF needs a WebAssembly encoder that is slow
  on phones.
- **Decision:**
  - The browser resizes, re-encodes (WebP, JPEG last resort) and strips metadata.
  - It renders plot thumbnails with Excalidraw's `exportToBlob`.
  - AVIF is dropped.
- **Consequences:** browser output is untrusted:
  - the server verifies hashes, signed size caps and image headers
  - thumbnails are moderated as images
  - thumbnails publish only when every element they show is approved

## ADR-008: Moderation: OpenAI first, Claude image checks, caps never bypass

- **Context:** OpenAI's moderation endpoint is free, but for images it covers only sexual content,
  violence and self-harm. Hate, harassment and illicit content are text-only, so hate symbols and
  hateful text inside images would go unchecked.
- **Decision:**
  - OpenAI on everything.
  - Claude (Haiku) checks images, including text inside them, for:
    - every image from trust level 0 users (normal API)
    - every image on a plot before its first growth applies (batch)
    - every reported image
  - Each check also stores a short image description for placement.
  - Borderline text goes to Claude.
  - A daily spend cap applies; at the cap, items stay pending and are never skipped.
- **Consequences:** this is the largest variable cost (`CLAUDE.md` section 13). Levers: faster trust
  promotion, skipping re-checks of already-checked images inside thumbnails, and cap tuning.

## ADR-009: Placement from direct embeddings; required plot descriptions

- **Context:** a summarize-then-embed step doubles AI cost. Plots with only drawings or images have
  no text.
- **Decision:**
  - Embed the one-line description (required at signup, editable anytime), text items, card source
    and image descriptions directly with Voyage `voyage-4-lite`, 512 dimensions, stored as
    `halfvec`.
  - Re-embed only when a hash of that text changes, after a quiet period.
  - If a plot still can't be placed, the owner picks a region.
  - Claude names regions and continents once each.
- **Consequences:** about 1 KB per plot embedding; the one-time free 200M tokens cover a long
  development and early launch period.

## ADR-010: Growth computed on read; attention batched

- **Decision:**
  - `earned_space` plus a timestamp, decayed in closed form on read.
  - Points are added in one `UPDATE`.
  - Footprints change in steps found by an indexed query.
  - The browser batches attention every 30 seconds, folded server-side into one row per plot,
    visitor and day, with an exact daily cap.
- **Consequences:** no job ever crawls every plot.

## ADR-011: Background work on Cron Triggers; GitHub Actions for CI only

- **Context:** GitHub's Additional Product Terms forbid using GitHub-hosted runners for "any other
  activity unrelated to the production, testing, deployment, or publication of the software
  project".
- **Decision:**
  - All production background work runs in the Worker's scheduled handler, in small claimed batches.
  - Actions only build, test and deploy.
  - Free plan: 5 cron triggers per account and 10 ms CPU. Network waits don't count as CPU, so batch
    jobs that are mostly API calls fit.
- **Source:** [GitHub Terms for Additional Products and Features, Actions](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features).

## ADR-012: Nightly encrypted backups from a Worker cron

- **Context:** Supabase's free plan has no backups. GitHub Actions is ruled out (ADR-011). A dump
  needs more CPU than the free plan's 10 ms.
- **Decision:**
  - A nightly Cron Trigger on Workers Paid (planned for launch, so no extra cost) connects to
    Postgres over TCP (`pg`, as in Cloudflare's guide).
  - It streams `COPY … TO STDOUT` per table, gzips with `CompressionStream`, and encrypts with a
    random AES-256-GCM key wrapped by an RSA-OAEP public key (Web Crypto).
  - It uploads to a private R2 bucket with multipart upload; retention (7 daily, 4 weekly) uses R2
    lifecycle rules.
  - The private key stays offline with the owner. The schema comes from the git migrations. Nothing
    sensitive is logged.
  - A restore is tested before launch.
- **Alternatives:**
  - Supabase Pro ($25/month, daily backups).
  - A cron job on the owner's computer (free, but unreliable).
  - GitHub Actions (terms).
- **Sources:**
  - [Workers limits: Paid cron CPU up to 15 min for intervals of an hour or more](https://developers.cloudflare.com/workers/platform/limits/)
  - [Connecting to PostgreSQL from Workers](https://developers.cloudflare.com/workers/tutorials/postgres/)
  - [R2 pricing](https://developers.cloudflare.com/r2/pricing/)
  - [Supabase pricing (free plan: no backups)](https://supabase.com/pricing)

## ADR-013: Google and GitHub sign-in only

- **Context:** email sign-in needs a paid or limited email sender.
- **Decision:** OAuth with Google and GitHub only in production. The local stack may use email
  through its built-in test mailbox.
- **Consequences:** no email cost and less account spam. The weekly digest goes through web push and
  in-app.

## ADR-014: Cold storage in R2 after 90 days without visits

- **Decision:** an hourly cron moves idle plots' content rows to R2 Standard (as a JSON file) and
  deletes them from Postgres. The thumbnail, layout entry and snapshot stay. An owner edit or a
  visitor opening the plot restores it.
- **Consequences:** keeps the free 500 MB database small. Restores cost one R2 read.

## ADR-015: Reports weighted by trust, with automatic re-checks

- **Decision:**
  - Weight 1.0 for level 2 (blurs immediately), 0.5 for level 1, 0.25 for level 0.
  - The content blurs at a summed weight of 1.0.
  - Every report triggers an immediate automated re-check; a flag blurs the content regardless of
    who reported it.
- **Consequences:** no single new account can hide someone else's content, but genuinely bad content
  still blurs quickly through the re-check.

## ADR-016: Comment deletion is soft; owners can delete on their plot

- **Decision:**
  - Authors and plot owners delete comments through one database function that sets `deleted_at`
    and `deleted_by`.
  - Hard deletes are not granted to clients.
  - Public views hide deleted comments; staff can still read them.

## ADR-017: i18n with next-intl; cookieless analytics

- **Decision:**
  - `next-intl` message catalogs from day one, with no hard-coded user-facing strings and no
    locale-prefixed routes yet (locale from preference or the browser).
  - IBM Plex Sans and Plex Sans Devanagari, so Hindi needs no font change (`docs/design.md`).
  - Cloudflare Web Analytics (free, cookieless). PostHog's free tier only if funnels need it, with a
    $0 billing limit.

## ADR-018: Abuse-material hash matching required before launch

- **Context:** OpenAI's image moderation does not cover sexual content involving minors as an image
  category (our ban on all sexual content still blocks it). Hash matching against known material is
  standard practice, and there are legal reporting duties.
- **Decision:**
  - PhotoDNA Cloud Service (free for qualifying services) before publishing.
  - Cloudflare's CSAM Scanning Tool (free) on cached content as a second layer. It blocks matches
    and emails us, but does not report for us.
  - Written legal reporting procedures for the US (NCMEC CyberTipline, 18 U.S.C. § 2258A) and India
    (POCSO Act, IT Act §67B, IT Rules 2021, National Cyber Crime Reporting Portal), confirmed by a
    lawyer.
- **Source:** [Cloudflare CSAM Scanning Tool](https://developers.cloudflare.com/cache/reference/csam-scanning/).

---

## Superseded

| Earlier choice                                    | Replaced by      |
| ------------------------------------------------- | ---------------- |
| tldraw editor                                     | ADR-005          |
| Server-rendered thumbnails                        | ADR-007          |
| AVIF images                                       | ADR-007          |
| Claude summaries before embedding; Sonnet default | ADR-009          |
| Tile pyramid in Phase 2                           | ADR-006          |
| GitHub Actions for tiles or backups               | ADR-011, ADR-012 |
| Vercel hosting                                    | ADR-002          |
| `voyage-4` with 1024-dimension vectors            | ADR-009          |

## Phase 0 implementation notes

- **Stack:** Next.js 16 (App Router, `src/`), React 19, TypeScript 5 (strict, plus
  `noUncheckedIndexedAccess`), Tailwind 4, Supabase CLI with Postgres 17, Vitest 5, ESLint 9 and
  Prettier 3. A single app at the repository root.
- **Known audit warning:** `micromatch` through `eslint-config-next`. It is a development
  dependency only and is left until Next publishes a fix.
- **Schema refinements beyond the brief:**
  - `staff` (private membership) and `region_visits`
  - one frontier region
  - `asset_sources` and `asset_uploads` for deduplication and ownership
  - moderation reason and time on items and comments
- **Blurred content** is withheld from the public views, not blurred with CSS, which would still send
  it to the browser.
- **Pending comments** are hidden from the plot owner too, so harassment never reaches its target
  before moderation.
