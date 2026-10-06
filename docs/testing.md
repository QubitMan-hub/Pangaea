# Testing strategy

The parts that must never break silently are the moderation pipeline, placement, and growth and
decay (`CLAUDE.md` section 10). Safety rules are tested where they are enforced: in the database.
Pure logic is tested as pure functions. The rest is tested in a real browser. **No test ever calls
a paid API.** Providers sit behind interfaces with deterministic fakes.

## Layers

| Layer               | Tool (all free)                                                        | What it proves                                                                                                | Runs                       |
| ------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------- |
| Database invariants | pgTAP via `supabase test db`                                           | RLS, column grants, guard triggers, public views: the rules a hand-crafted API request could otherwise bypass | CI, every push             |
| Unit                | Vitest                                                                 | Pure logic: decay math, placement, moderation decisions, cost caps, paste detection, tidy-up, schedules, env  | CI, every push             |
| Property-based      | Vitest + `fast-check` (added in Phase 3 and 4)                         | Invariants over random inputs: decay never increases, caps never exceeded, placement never overlaps           | CI                         |
| Integration         | Vitest against local Supabase                                          | Route handlers and jobs with fake providers: a full moderation run from pending to published                  | CI (database job)          |
| End-to-end          | Playwright (pre-installed Chromium)                                    | The first minute, posting, moderation feedback, navigation, on phone and desktop sizes, light and dark        | CI from Phase 1            |
| Accessibility       | `@axe-core/playwright` plus a manual keyboard and screen-reader script | WCAG 2.2 AA on every screen                                                                                   | CI, plus manual each phase |
| Performance         | Lighthouse (mobile, slow 4G, 4× CPU) and Playwright frame-time traces  | The speed budgets in `docs/design.md` section 9                                                               | Each phase, reported       |
| Runtime parity      | `npm run preview` (workerd, Cloudflare's runtime)                      | The app, job routes and cron handler work on Workers, not just in Node                                        | Each phase                 |

## Moderation pipeline

**Database (done in Phase 0, 70 assertions):**

- client-created or edited content is forced to `pending`
- clients can't write moderation columns, approve, or bypass trust gates
- public views show approved content only, and blurred content without its body
- assets must be approved for an item to be public
- deleted comments vanish publicly but stay stored
- report weights come from the reporter's trust, never the client

**Unit (Phase 1)**, in the `ModerationService` decision engine:

- OpenAI scores map to approve, reject or borderline, with thresholds at their edges
- Claude is required exactly when the rules say so: uploader at level 0, plot starting to grow,
  reported image
- **the daily cap holds work as pending and never approves it**, tested at, just under and just
  over the cap
- a hash that already passed a check is not re-checked for that check
- thumbnail publishing needs every element version to be approved: one stale element blocks it
- card source text is checked as text
- the abuse-hash hook runs first, and a match blocks publishing and starts the reporting procedure

**Integration (Phase 1):**

- upload, finalize, OpenAI fake, Claude fake, approve, copied to the public bucket, snapshot
  version bumped
- the rejected path: owner sees the reason, appeal created, staff overturns

**End-to-end (Phase 1):**

- paste an image: it appears instantly with "In review", then goes public when the fake approves it
- a visitor never sees it before that

## Placement (Phase 3)

- **Text gate:** the same normalized text produces the same hash, so no Voyage call. Whitespace or
  case-only edits don't count as change. The quiet period is respected.
- **Embedding input:** description first, then text, card source and image descriptions, trimmed
  to the token budget deterministically.
- **Region choice:**
  - above the threshold, nearest region
  - below it, frontier
  - owner-chosen plots are never moved automatically
- **Spiral placement** (property test): the free cell found is the nearest by spiral order, never
  occupied, and never overlaps an existing footprint.
- **Stability:**
  - a small embedding change doesn't move the plot; a large one does
  - the whole map is never reshuffled: placing N plots never moves an already-placed plot
- **Labels:** Claude is asked once per new region or continent; a cached label is never re-requested.
- **Fakes:** Voyage and Claude fakes return fixed vectors and labels, so tests are deterministic.

## Growth and decay (Phase 4)

- **Closed form:** `earned(t)` at known points; exactly half after one half-life of inactivity;
  unchanged within the grace period after owner activity.
- **Property tests:**
  - decay is monotonically non-increasing without new points
  - adding points then decaying equals decaying then adding, at the same time
  - bringing the value up to date is idempotent
- **Daily cap:** for any sequence of attention batches from one visitor in a day, the total credited
  is at most the cap, and `credited_score` matches the sum.
- **Anti-gaming:**
  - owners viewing their own plot earn nothing
  - dwell is capped at the real elapsed time
  - signed-out visitors only increase the display count
- **Growth gate:** credits are held until every image on the plot has passed the Claude check.
- **Footprint steps:** the computed next step-crossing time is correct; resizing never overlaps
  neighbors (property test over random neighborhoods).
- **Cold storage:** move to R2 then restore gives an identical plot (a round-trip test).

## Cost guards (every phase)

- Per-plot and per-user limits are enforced at the API, and at the database where possible.
- `ai_spend_daily` accounting matches the token usage the fakes report.
- Unit tests fail if any code path tries a real network call: providers are injected, and the
  Vitest environment has no keys.

## Usability

At the end of each phase, a 5-person script (tasks and what to watch for) goes into the phase
report, along with what changed in response to the previous round.
