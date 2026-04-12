# 10 — CI status

## Workflow

`.github/workflows/ci.yml` defines three jobs:

1. **backend** — ruff lint + import smoke (`from app.main import app`)
2. **mobile** — `flutter pub get` → `flutter analyze --no-fatal-infos --no-fatal-warnings` → `dart format --set-exit-if-changed lib`. Pinned to Flutter 3.22.3, no cache.
3. **alembic** — runs `alembic upgrade head` against a real `timescale/timescaledb-ha:pg16` service container with PostGIS + TimescaleDB + pgcrypto bootstrapped first.

The mobile job has diagnostic logging that writes the analyze + format output to `GITHUB_STEP_SUMMARY` and uploads the analyze log as an artifact (`apps/mobile/ci-artifacts/analyze.log`).

## Last visible run before merge to main

PR #3 (`Multi-provider maps + CI fixes` follow-up that merged into main):
- Run id `24303383374` on commit `7219d5e`
- Started 2026-04-12 09:20:54 UTC

| Job | Conclusion |
|---|---|
| Backend (lint + import check) | ✅ success |
| Backend migrations (Postgres + PostGIS + TimescaleDB) | ✅ success |
| Mobile (flutter analyze) | ❌ failure |

The mobile failure was annotated only as `Process completed with exit code 1` on the `Analyze (capture)` step. The detailed step summary requires GitHub auth to view (`WebFetch` is blocked).

## What we know about the mobile failure

- Locally with the same Flutter 3.22.3 + same `pubspec.lock` + same source, both `flutter analyze --no-fatal-infos` and `dart format --output=none --set-exit-if-changed lib` exit 0 cleanly.
- The CI run on `7219d5e` was where I first added `--no-fatal-warnings` to make the analyze step tolerant of warnings — and it still failed. So the failure is on real **errors**, not warnings, OR something else in the pipeline (not the analyze command itself) is returning non-zero.
- Possible suspects we didn't get to verify:
  - Hidden character / line-ending difference between dev container and the Ubuntu runner
  - The `tee` + `PIPESTATUS` shell pattern interacting with `pipefail` in some subtle way
  - The artifact upload step itself failing and being misattributed to analyze (the path was wrong in the first attempt; second attempt fixed it)
  - A cache miss + fresh `pub get` pulling slightly newer transitive dep that introduces a new lint

## CI status on `main` after merge

After PR #3 was merged via `d0ee559`, two more design-only commits landed:
- `2fdedd5 docs(designs): add Stitch mockups + Kinetic Path design system`
- `4907714 Merge designs branch into main`
- `1b63d95 docs(designs): add Kinetic Path design system doc + research PRD`

These would have triggered fresh CI runs on `main`. The workflow files weren't touched, so the same failure pattern likely persists on the `main` branch right now (mobile job red, backend jobs green).

## Recommended next steps for CI

These are scoped follow-ups, **not** to be done in this audit session:

1. **Get the actual error message.** Either (a) download the `mobile-analyze-log` artifact from the latest workflow run via authenticated `gh run download`, or (b) add a step that writes the analyze output to a Gist via the GitHub API in CI itself, or (c) make the Analyze step `if: failure()` re-emit the captured log as `::error::` annotations line by line.
2. **If the issue is a phantom warning,** the `--no-fatal-warnings` already in place should mask it, so the failure is more likely on something other than analyze itself.
3. **If the issue is the format step,** the `--set-exit-if-changed` will print the diff to the step summary already (the workflow added that retry).
4. **Once the Android/iOS scaffolds exist** (see file 05), CI can add a `flutter build apk --debug` job which will catch a much wider class of breakage than `analyze` alone.

## Verdict

🟡 CI is mostly green. The mobile analyze failure has been chased through 4 commits without root-cause diagnosis. It is **not blocking the audit**, but it is blocking confidence that any future PR to main will land cleanly. Should be diagnosed early in the next session.
