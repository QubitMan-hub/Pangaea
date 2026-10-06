# Pangaea

One infinite map of ideas, shared by the whole world. Every person gets a plot, and Pangaea
arranges plots about related ideas into continents you can explore.

**Status:** Phase 0 (setup), reworked for the cost-first brief. Phase 1 (plots and the first
minute) is next.

| Document                                       | What it covers                                                                                           |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| [`CLAUDE.md`](CLAUDE.md)                       | The brief and source of truth: product rules, cost rules, phases, launch checklist, cost notes           |
| [`docs/architecture.md`](docs/architecture.md) | How it works: read path, viewer, editor, uploads, moderation, placement, growth, jobs, backups           |
| [`docs/decisions.md`](docs/decisions.md)       | Why: architecture decision records                                                                       |
| [`docs/design.md`](docs/design.md)             | How it looks and feels: the living atlas, tokens, type, motion, components, speed budgets, accessibility |
| [`docs/testing.md`](docs/testing.md)           | How we know it works                                                                                     |

## Run it locally

You need Node.js 22 (`nvm use`) and Docker running (the local Supabase stack runs in containers).
Everything below is free.

```bash
npm install
npm run db:start      # local Supabase; applies all migrations (first run pulls images)
npm run env:local     # writes .env.local with local Supabase and storage credentials
npm run dev           # http://localhost:3000
```

- **Sign-in locally:** production uses Google and GitHub only. Locally, use email sign-in. Messages
  land in the local Mailpit inbox at http://127.0.0.1:54324 and no real email is sent. To test
  OAuth, create free OAuth apps, export the `SUPABASE_AUTH_EXTERNAL_*` variables from
  `.env.example`, and set `enabled = true` in `supabase/config.toml`.
- **Run on Cloudflare's runtime** (workerd), exactly as production will:
  ```bash
  cp .dev.vars.example .dev.vars   # then add the server values from .env.local
  npm run preview                  # builds with OpenNext and serves on http://localhost:8787
  ```
  Test the cron handler with `curl "http://localhost:8787/__scheduled?cron=*+*+*+*+*"` (start the
  preview with `--test-scheduled`).
- **Supabase Studio:** http://127.0.0.1:54323. Stop the stack with `npm run db:stop`.

## Scripts

| Command                     | What it does                                                                     |
| --------------------------- | -------------------------------------------------------------------------------- |
| `npm run dev`               | Next.js dev server (with Cloudflare bindings via OpenNext)                       |
| `npm run build`             | Next.js production build                                                         |
| `npm run cf:build`          | OpenNext build for Cloudflare Workers                                            |
| `npm run preview`           | OpenNext build, then serve in workerd locally                                    |
| `npm run deploy` / `upload` | Deploy to Cloudflare (needs the owner's account; run the deploy checklist first) |
| `npm run check`             | Lint, typecheck, format check, unit tests                                        |
| `npm run test:db`           | pgTAP database tests (RLS, moderation, ownership, comments, reports)             |
| `npm run db:reset`          | Recreate the local database from migrations                                      |
| `npm run db:types`          | Regenerate `src/lib/supabase/database.types.ts` (CI checks it is current)        |
| `npm run env:local`         | Write `.env.local` from the running local stack (`-- --force` to overwrite)      |
| `npm run cf-typegen`        | Generate Cloudflare binding types                                                |

After changing a migration, run `npm run db:reset && npm run db:types && npm run test:db`.

## Layout

```
src/
  app/                 Next.js App Router (pages, api/jobs/[job] for cron work)
  i18n/                next-intl config; messages/ holds the catalogs
  lib/env/             Env validation (zod); server.ts is server-only
  lib/jobs/            Cron schedule → job mapping, cron secret check
  lib/supabase/        Clients (browser, server, admin) and generated types
worker.ts              Cloudflare Worker entry: OpenNext fetch + cron handler
wrangler.jsonc         Cloudflare config (crons, observability; secrets never here)
open-next.config.ts    OpenNext config (static-assets cache, no ISR)
supabase/migrations/   Schema, access control, safety triggers, storage, reference data
supabase/tests/        pgTAP tests
messages/              Translation catalogs (en; hi next)
docs/                  Architecture, decisions, design, testing
```

## How data is protected

The safety rules are enforced in the database, so a bug or a hand-crafted API request can't bypass
them:

- **Row Level Security on every table**, with privileges granted explicitly, column by column for
  writes.
- **Nothing unmoderated is public.**
  - Visitors read items and comments only through the `*_public` views: approved rows, or reported
    ("blurred") rows with their content withheld.
  - An item is public only while its image is approved too.
- **Clients can't approve their own content.** New or edited content, media or descriptions are
  forced back to `pending`.
- **Ownership.**
  - Only owners write their plot's items, and only with images they uploaded.
  - Placement, size, embeddings and thumbnails are system-managed.
- **Soft deletes.** Comments are hidden by authors or plot owners through `delete_comment()` and
  stay stored for moderators.
- **Reports** are weighted by the reporter's trust level, which the database looks up itself.
- **Trust levels** gate item types (webpages and video need level 1).

The service-role client (`src/lib/supabase/admin.ts`) bypasses all of this. Use it only in trusted
server code.

## Costs

Running cost is the top constraint. See `CLAUDE.md` sections 2, 12 and 13 for the rules, the spending
caps to set before launch, and the cost estimates. In short: development is free, and public launch
plans for Workers Paid ($5/month).

**Measuring CPU per request** (to know when the free plan's 10 ms limit is near): once the Worker is
deployed, Cloudflare dashboard → Workers → pangaea → Observability shows CPU time per invocation
(p50/p99) per route and per cron run. Locally, workerd doesn't enforce or report CPU limits.

## CI

`.github/workflows/ci.yml` (GitHub Actions is used only for building and testing, per GitHub's terms):

1. Lint, typecheck, format check, unit tests, Next.js build and the OpenNext Cloudflare build.
2. Boot Supabase, apply migrations, run pgTAP tests and the database linter, and check that
   generated types are current.
