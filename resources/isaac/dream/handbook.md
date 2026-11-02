# Dreaming and crew habits

A habit is a short, crew-private lesson. Only **active** habits are included in
that crew's system prompt. Habits are stored under `dream/<crew>/<id>.edn` in
the Isaac root, not in config or the crew workspace. Each record has evidence
(`{:session "greenhouse" :entries ["e-7f3a"]}`), an append-only history, and,
for dreamed habits, the diary timestamp in `:dream`. Reinforcement of proposed or active habits adds a
history event without changing state. A replacement is a new habit with
`:supersedes`; approval retires its predecessors and records `:superseded-by`.
Deleting a session leaves missing evidence rather than deleting the habit.

## Configure dreams

Dreaming is **off** by default. In `config/isaac.edn` set shared crew defaults,
then enable individual crews in `config/crew/<id>.edn`:

```clojure
:defaults {:crew {:dream {:schedule "0 3 * * *" :approval :manual}}}
;; In the crew file: {:dream {:enabled true}}
```

The five-field cron schedule uses the configured `:tz`; an enabled crew
without a resolved schedule fails config validation. Override `:schedule`
per crew (e.g. `"0 * * * *"`), `:model` to choose a different analysis model,
`:approval` to `:auto`, `:batch` to a positive message count (default 400), and `:digest` to `{:comm "discord" :to "operator"}`.
Otherwise the crew's model and `:attention :notify` destination are used.
The shared scheduler reconciles tasks when config reloads. `dream__propose`
and the active-habits prompt section work regardless of `:dream :enabled`.

## What happens at night

Code obtains a per-crew lock (one-hour expiry), gathers user and assistant
message text in the window after the watermark through the dream start time,
and drops tool calls and results. `--since` overrides the watermark for this
run; `--until` overrides the end. Both accept ISO instants or dates (midnight
UTC). The window is processed oldest first in batches of `dream.batch` messages
(default 400), with one model call per batch. Messages sharing a timestamp stay
together, even when this makes a batch larger than its configured size. Lines
are labeled `<session>#<n>` across all batches. Every prompt includes the crew
soul and current proposed and active habits with ids, lessons, and states so
later batches can reinforce earlier proposals. Citations outside the current
batch are dropped. Success moves the watermark to the window's end (never
backward); a failed batch leaves it at the last message of the last completed
batch, or unchanged if none completed. No new messages: no model call or digest.
The diary records the effective window, completed batch count, proposals and
reinforcements across batches, and failures. One digest is sent per run for
proposals or failure.
The diary lives under
`dream/<crew>/diary/<timestamp>.edn`. A digest goes to the configured
notification destination only for new proposals or failure; a quiet dream
still writes a diary entry.

## Operator CLI

- `isaac dream run --crew <id> [--since <date-or-instant>] [--until <date-or-instant>]` — run now, even for a disabled crew (but not
  without new messages).
- `isaac dream diary --crew <id>` — recent entries, newest first.
- `isaac dream list [--crew <id>] [--state proposed]` — inspect all crews or
  one crew. An unknown crew is an error.
- `isaac dream show <habit-id> --crew <id>` — show history and quoted lines
  read back from the evidence's session/entry ids; deleted evidence is marked
  missing.
- `isaac dream approve <id> --crew <id> [--lesson "reworded lesson"]` —
  approve and retire superseded habits, or create an approved replacement
  with an immutable new lesson.
- `isaac dream reject|retire|wipe --crew <id>` — manage this crew's habits.

For a live “remember this” moment grant `:dream/propose`. The
`dream__propose` tool takes `lesson` only: code attaches the calling session
and its most recent user-message entry id as evidence. It does not initiate
a dream. No `:session/list` or `:session/read` grant is needed for scheduled
code-run dreaming.
