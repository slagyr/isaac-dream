# 🍏 Isaac Dream 💭

Dreaming for [Isaac](https://github.com/slagyr/isaac): a crew reviews its
conversations and distills them into **habits** that only that crew sees.

Depends on [isaac-foundation](https://github.com/slagyr/isaac-foundation) and
[isaac-agent](https://github.com/slagyr/isaac-agent).

[![Dream](https://github.com/slagyr/isaac-dream/actions/workflows/ci-tests.yml/badge.svg)](https://github.com/slagyr/isaac-dream/actions/workflows/ci-tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Clojure](https://img.shields.io/badge/Clojure-1.11%2B-blue?logo=clojure)](https://clojure.org)
[![Babashka](https://img.shields.io/badge/Babashka-1.3%2B-red?logo=clojure)](https://babashka.org)
[![Java](https://img.shields.io/badge/Java-21%2B-orange?logo=openjdk)](https://openjdk.org/)

## Vocabulary

- **Dream** — a turn in which a crew reads its recent conversations and
  proposes habits.
- **Habit** — a short lesson private to one crew. Not a skill.
- **State** — `proposed`, `active`, `rejected`, or `retired`. Only `active`
  habits reach the model.
- **Promoter** — what moves `proposed` to `active`: the operator CLI
  (`:manual`, the default) or per-crew `dream.<crew>.approval :auto`.

## What's here

- Module `isaac.dream` (`isaac.dream.module/create-module`): crew-scoped EDN
  habits, the grant-gated `dream__propose` tool, manual/auto approval, and
  an active-only system section at order 900.
- Operator CLI: `isaac dream list|approve|reject|retire|wipe --crew <id>`.
- [Dream handbook](resources/isaac/dream/handbook.md).

## Development

```bash
bb spec       # speclj specs
bb features   # gherclj scenarios
bb ci         # lint + spec + features
```

Add `-A:dev-local` style overrides (see `deps.edn`) to test against sibling
checkouts of isaac-foundation and isaac-agent.
