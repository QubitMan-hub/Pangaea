# Pangaea

Reddit, but as one giant whiteboard. One infinite board shared by the whole world, where every user
gets a plot and Claude arranges plots into "continents" of related ideas.

The product brief, which is the source of truth, is in [`CLAUDE.md`](CLAUDE.md). Design decisions
and open questions are in [`docs/decisions.md`](docs/decisions.md).

**Status:** Phase 0 (setup) is done. Phase 1 (plots, auth, editor, moderation) is next.

## Run it locally

You need:

- Node.js 22 (`nvm use` reads `.nvmrc`)
- Docker, running (the local Supabase stack runs in containers)

```bash
npm install
npm run db:start      # starts local Supabase and applies all migrations (first run pulls images)
npm run env:local     # writes .env.local with the local Supabase URL and keys
npm run dev           # http://localhost:3000
```

Local Supabase Studio is at http://127.0.0.1:54323. Stop the stack with `npm run db:stop`.

To point at a hosted Supabase project instead, copy `.env.example` to `.env.local` and fill in the
values from the project's API settings.

## Scripts

| Command                              | What it does                                                          |
| ------------------------------------ | --------------------------------------------------------------------- |
| `npm run dev`                        | Next.js dev server                                                    |
| `npm run build` / `start`            | Production build / serve it                                           |
| `npm run check`                      | Lint, typecheck, format check and unit tests (run before pushing)     |
| `npm run lint`                       | ESLint (zero warnings allowed)                                        |
| `npm run typecheck`                  | Generates Next route types, then `tsc --noEmit`                       |
| `npm run format`                     | Prettier, write mode (`format:check` to verify only)                  |
| `npm test`                           | Vitest unit tests (`test:watch` for watch mode)                       |
| `npm run test:db`                    | pgTAP database tests: RLS, moderation and ownership rules             |
| `npm run db:start` / `db:stop`       | Start / stop local Supabase                                           |
| `npm run db:reset`                   | Recreate the local database from migrations and `seed.sql`            |
| `npm run db:new-migration -- <name>` | Create a new timestamped migration file                               |
| `npm run db:types`                   | Regenerate `src/lib/supabase/database.types.ts` from the local DB     |
| `npm run env:local`                  | Write `.env.local` from `supabase status` (`-- --force` to overwrite) |

After changing a migration: `npm run db:reset && npm run db:types && npm run test:db`. CI fails if
the generated types are out of date.

## Layout

```
src/
  app/                    Next.js App Router pages
  lib/
    env/                  Env var validation (zod). server.ts is server-only.
    supabase/             Clients: browser, server (user session), admin (service role)
                          and generated database.types.ts
supabase/
  migrations/             Schema, access control, safety triggers, storage, reference data
  tests/database/         pgTAP tests
  seed.sql                Intentionally empty, see the note inside
scripts/                  Dev scripts (run with tsx)
docs/decisions.md         Decisions, deviations from the brief, open questions
```

## How data is protected

The safety rules from the brief are enforced in the database, not just in app code, so a bug or a
hand-crafted API request can't bypass them:

- **Row Level Security on every table.** A test fails if any table lacks it.
- **Unmoderated content is never public.** Visitors read items and comments only through the
  `plot_items_public` and `comments_public` views, which return approved rows (and reported,
  "blurred" rows with the content withheld). The base tables are readable only by their owner and
  staff. Pending comments are hidden even from the plot owner.
- **Clients can't approve their own content.** Column-level grants stop clients writing moderation
  fields, and triggers force new or edited content back to `pending`. Moving an item keeps its
  approval; changing its content does not.
- **Only owners write to their plot's items.** Everything else about a plot (placement, size,
  earned space, summary, thumbnail) is system-managed and written with the service role.
- **Trust levels** gate item types at the database level (webpages, video and documents need
  level 1).
- **Uploads** go to a private bucket. Only approved images are copied to the public `media` bucket.

The service-role client in `src/lib/supabase/admin.ts` bypasses all of this. Use it only in trusted
server code.

## CI

`.github/workflows/ci.yml` runs two jobs on every push to `main` and every pull request:

1. lint, typecheck, format check, unit tests, production build
2. boots Supabase, applies migrations, runs the pgTAP tests and the database linter, and checks
   that generated types are current
