# Dreaming and crew habits

A habit is a short, crew-private lesson. Only **active** habits are included in
that crew's system prompt. Habits are stored under `dream/<crew>/<id>.edn` in
the Isaac root, not in config or the crew workspace. Each record has evidence
(`{:session "greenhouse" :entries ["e-7f3a"]}`), an append-only history, and,
for dreamed habits, the diary timestamp in `:dream`. Reinforcement adds a
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
`:approval` to `:auto`, and `:digest` to `{:comm "discord" :to "operator"}`.
Otherwise the crew's model and `:attention :notify` destination are used.
The shared scheduler reconciles tasks when config reloads. `dream__propose`
and the active-habits prompt section work regardless of `:dream :enabled`.

## What happens at night

Code obtains a per-crew lock (one-hour expiry), gathers new user and assistant
message text since the previous watermark, and drops tool calls and results.
It labels lines `<session>#<n>` and makes one model call with the crew's soul,
active habits with ids, and the window. The model may propose habits or
reinforce active ones; citations outside the window are dropped and recorded.
On success the watermark advances to the dream start time. No new messages:
no model call or digest. A failed model call preserves the watermark and
writes a failure diary entry. The diary lives under
`dream/<crew>/diary/<timestamp>.edn`. A digest goes to the configured
notification destination only for new proposals or failure; a quiet dream
still writes a diary entry.

## Operator CLI

- `isaac dream run --crew <id>` — run now, even for a disabled crew (but not
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
