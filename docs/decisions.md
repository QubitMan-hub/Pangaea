# Decisions and open questions

A running log of choices made while building Pangaea, where they refine or deviate from the brief
in `CLAUDE.md`, and what still needs a decision from the product owner.

## Phase 0

### Stack and versions

| Piece             | Version                | Note                                                                                       |
| ----------------- | ---------------------- | ------------------------------------------------------------------------------------------ |
| Next.js           | 16.3                   | App Router, `src/` dir. Read `AGENTS.md`: 16 changes several APIs.                         |
| React             | 19.2                   |                                                                                            |
| TypeScript        | 5.x                    | Strict, plus `noUncheckedIndexedAccess`. TS 7 is out but Next's tooling still targets 5.x. |
| Tailwind CSS      | 4                      |                                                                                            |
| Supabase          | CLI 2.120, Postgres 17 | pgvector in the `extensions` schema                                                        |
| Vitest            | 5                      | Unit tests. Database tests use pgTAP via `supabase test db`.                               |
| ESLint / Prettier | 9 / 3                  | `no-explicit-any` is an error, per brief 8                                                 |

The repo is a single Next.js app at the root, not a monorepo. That is enough for the MVP; the
Phase 6 sandboxed-HTML origin can be a separate deployable later.

tldraw, PixiJS, the Anthropic SDK and Voyage are not installed yet. Each comes in with the phase
that uses it.

### Embeddings: Voyage `voyage-4`, 1024 dimensions

The `voyage-4` family (`voyage-4-large`, `voyage-4`, `voyage-4-lite`) defaults to 1024 dimensions
and its models produce compatible embeddings. Vector columns are `vector(1024)`. `plots` records
`embedding_model` so a later model change can be detected and re-embedded. The model is configurable
with `VOYAGE_MODEL`.

### Schema refinements to the brief's data model

- **`users`** references `auth.users`. Handles are 3 to 24 characters, lowercase letters, digits
  and underscores. Users can change only their handle.
- **`staff`** (new) holds moderators and admins, kept out of `users` so staff membership is never
  public. Needed for the admin page and for policies that let staff read pending content.
- **`regions.is_frontier`** marks the single frontier region (brief 5.1 step 5). It is created by a
  migration at the world origin (0, 0). Only the frontier may have no centroid.
- **`plots`**: `owner_id` is unique (one plot per user); `(grid_x, grid_y)` is unique; added
  `embedding_model`; `status` is `active` or `suspended`. The units of `base_size` and
  `earned_space` are decided in Phase 4 with the no-overlap approach.
- **`plot_items` / `comments`**: added `moderation_reason` (shown to the owner on rejection) and
  `moderated_at`. Item `content` must be a JSON object of at most 64 KB; media lives in Storage.
- **`region_visits`** (new) records which regions a user has visited. Needed for the "wander"
  button and the "visit a new region" mission.
- **`reports`**: added `resolved_by` and `resolved_at`; one report per reporter per target.
- **`mission_completions`**: one completion per user per mission, since the MVP missions are
  one-time.
- **`attention_events`**: written only by the server, so per-visitor daily caps can't be bypassed.
- The four MVP missions are inserted by a migration. Their reward points are placeholders.

### Access model

- RLS on every table. Supabase's default "grant all to anon and authenticated" is revoked and
  privileges are granted back table by table, and column by column for writes.
- Public reads of items and comments go through two views that run with the owner's rights. This is
  the single place that decides what the public can see. Supabase's advisor flags views like this;
  it is intentional and commented in the migration.
- Guard triggers run as the invoker so they can tell clients from the server with `current_user`.
  Security-definer helpers live in a `private` schema the Data API doesn't expose, so clients can't
  call them as RPCs.
- **Blurred content is withheld, not blurred client-side.** A reported item keeps its slot on the
  plot, but its content is not sent to visitors at all until review finishes. A CSS blur would still
  ship the content to the browser.
- **Pending comments are hidden from the plot owner** as well as everyone else, so harassment never
  reaches its target before moderation.

### Storage

Three buckets: `uploads` (private, owner-only, unmoderated), `media` (public, only approved images,
written by the server) and `thumbnails` (public, server-rendered PNGs). Images are limited to PNG,
JPEG and WebP up to 10 MB. SVG is excluded because it can carry script. GIF is excluded for now
because image moderation usually checks a single frame.

### Seed data

`supabase/seed.sql` is intentionally empty. Seed plots will be loaded by a TypeScript script that
sends every item through `ModerationService` (brief 8), which arrives in Phase 1.

### tldraw license (brief 3: required before shipping anything public)

As of October 2026, per tldraw.dev/community/license:

- The SDK is free **in development only**. It will not work in production without a valid license
  key.
- **Trial:** free, 100 days, one per company. Sends a hash of the license key for analytics, and
  stops working when it expires.
- **Hobby:** free, for non-commercial projects, granted at tldraw's discretion. The "made with
  tldraw" watermark must stay visible on the canvas.
- **Commercial:** custom pricing through their sales team, with startup pricing available. No
  watermark, no data collection.

What this means for Pangaea: Phase 1 can be built and tested locally without a key. Before any
public deployment, even a beta, we need a license. If Pangaea is or will become a business, that
means a commercial license (or a trial to bridge a short beta). Hobby only fits if it stays strictly
non-commercial.

### Known audit warnings

`npm audit` reports high-severity advisories in `micromatch` via `eslint-config-next`. This is a
development-only dependency (linting) and doesn't ship to users. Clearing it needs a breaking
`eslint-config-next` downgrade, so it is left until Next publishes a fix.

## Open questions for the product owner

1. **Moderation vendors.** The brief asks for one text and one image API. Do you have a preference?
   Recommendation: one provider that covers both text and images keeps Phase 1 simpler, with the
   `ModerationService` interface letting us split them later.
2. **tldraw license tier.** Commercial, trial or hobby (see above)? Needed before public launch,
   not before Phase 1 development.
3. **One report blurs content immediately** (brief 5.4.4). That lets any one user hide anything
   until a moderator looks. Is that OK for launch, or should we require several reports, or weight
   reports by the reporter's trust level?
4. **Can plot owners delete comments on their own plot?** Currently only the author (and staff, via
   the server) can.
5. **Does attention from signed-out visitors count toward growth?** It is much easier to fake.
   Proposal: count views from anyone, but only signed-in visitors count for dwell, comments and
   return visits.
6. **Handles at signup.** Pick one during onboarding (proposal), or generate one and let users
   change it?
