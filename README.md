# Pangaea

One infinite map of ideas. Scope, rules and decisions are in [`CLAUDE.md`](CLAUDE.md); the visual
system and first-minute flow are in [`docs/design.md`](docs/design.md).

## Run it locally

You need Node.js 22 and Docker. Everything here is free.

```bash
npm install
npm run db:start     # local Supabase; applies the migration (first run pulls images)
npm run env:local    # writes the local Supabase keys to .env.local
npm run dev          # http://localhost:3000
```

- Put your own keys (see `.env.example`) in `.env`. Both `.env` and `.env.local` are git-ignored,
  and Next.js and Wrangler read both.
- Local sign-in uses email through the Mailpit inbox at http://127.0.0.1:54324. To try Google or
  GitHub, create free OAuth apps, set the `SUPABASE_AUTH_EXTERNAL_*` keys and enable them in
  `supabase/config.toml`.
- `npm run preview` builds for Cloudflare and serves the app in workerd, the same runtime as
  production.

## Scripts

| Command                             | What it does                                                   |
| ----------------------------------- | -------------------------------------------------------------- |
| `npm run check`                     | Lint, typecheck, format check, unit tests                      |
| `npm run test:db`                   | Database security tests: RLS, ownership, moderation            |
| `npm run db:reset`                  | Rebuild the local database from the migration                  |
| `npm run db:types`                  | Regenerate `src/lib/supabase/database.types.ts` (CI checks it) |
| `npm run preview` / `deploy`        | Cloudflare build, then serve locally / deploy                  |
| `npx supabase migration new <name>` | Start a new migration                                          |

After changing the schema: `npm run db:reset && npm run db:types && npm run test:db`.

## Layout

```
src/app/            Pages and layout
src/lib/env.ts      Env validation (values never echoed in errors)
src/lib/supabase/   Browser, server and admin (RLS-bypassing) clients, generated types
src/i18n/           next-intl config; strings live in messages/
supabase/           config.toml, the migration, database tests
```

## CI

GitHub Actions (CI only) runs `npm run check` and the Cloudflare build. It then boots Supabase,
applies the migration, and runs the database tests, the database linter and the generated-types
check.

To see CPU per request once deployed, open the Cloudflare dashboard → Workers → pangaea →
Observability.
