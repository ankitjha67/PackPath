# PackPath — repo scaffold, bug inventory & fix plan

_Triage snapshot, 2026-11-18, at `main` = v1.0.0 (`f5a1ce3`). Sources: full
feature-vs-README audit, CodeRabbit review history, fresh TODO/dead-end/lint
sweeps, and git state._

## 1. Repo scaffold

```
PackPath/
├── apps/
│   ├── mobile/   (239 files) Flutter 3.41-pinned app
│   │   ├── lib/core/        api_client, token_storage, server_config, ws_*, theme/
│   │   ├── lib/features/    map, trips, chat, safety, settings, auth, hazards, …
│   │   ├── lib/shared/      DTO models
│   │   ├── test/            token_storage_test (4 tests, in CI)
│   │   └── android/ ios/ web/  platform shells + teal icon set
│   └── backend/  (137 files) FastAPI + SQLAlchemy async
│       ├── app/routers/     auth, trips, waypoints, safety, scheduled, documents, …
│       ├── app/services/    maps/{7 providers}, sms, scheduled_sender, push, …
│       ├── app/models/ app/ws/  ORM + trip socket
│       ├── alembic/         migrations 0001–0020
│       ├── tests/           pytest (6, in CI)
│       └── Dockerfile + docker-entrypoint.sh
├── designs/      36 mockup sets + Kinetic Path design system (implemented)
├── docs/         architecture, PRD, roadmap, audits, screenshots/
├── infra/        docker-compose (postgres+redis+backend), .env.example
└── .github/      ci.yml (backend | mobile | migrations | CodeRabbit) + release.yml
```

**Local folder state:** working tree clean. Three untracked artifacts
(`app179…zip`, `apps/backend/media/`, generated debug assets) are now
gitignored (commit `74b8b2c`, local).

## 2. Bug inventory

### Found in this sweep — fixed locally, awaiting push (branch `claude/fix-selfhost-media-urls`)

| # | Sev | Bug | Fix |
|---|-----|-----|-----|
| 1 | 🔴 | Chat attachments & trip gallery built media URLs from compile-time `Env.apiBaseUrl` (`chat_screen.dart:847`, `trip_gallery_screen.dart:16`) → broken images for any self-hoster with a custom Server URL | `ServerConfig.active` (synced by controller) used at both call sites — commit `74b8b2c`, tests green |
| 2 | 🟡 | Runtime uploads / debug assets / stray zip untracked & un-ignored | `.gitignore` entries in same commit |

### Open — mobile

| # | Sev | Bug | How to fix |
|---|-----|-----|------------|
| 3 | 🟠 | 21 × `use_build_context_synchronously` — `BuildContext` used after `await` without a mounted guard; latent crash/wrong-screen on fast navigation | Audit each site: capture `ScaffoldMessenger`/`Navigator` before the `await`, or guard with `context.mounted` (pattern already used in `_resolve`) |
| 4 | 🟡 | `ola_vector_style.dart` imports `vector_tile_renderer` without declaring it (`depend_on_referenced_packages`) — works only via a transitive dep of `vector_map_tiles` | Add it to `pubspec.yaml` with the version the lockfile already resolves |
| 5 | 🟡 | 1 × `deprecated_member_use` | Replace per analyzer hint |
| 6 | 🟡 | Onboarding redirect reads build-time `hasSeenOnboardingProvider` (`router.dart:36`) — unauthenticated deep links can bounce to /onboarding after completion until restart (mitigated by public-route design) | Make it a `StateProvider`, update it when onboarding completes |
| 7 | 🟡 | Firebase config stubbed (`push_service.dart:27` TODO) — FCM push inert until a real project is wired | Needs your Firebase project: drop in `google-services.json` + real `firebase_options.dart` |
| 8 | ⚪ | 463 × `require_trailing_commas`, 11 × `prefer_const*` — style only | One mechanical `dart fix --apply` + format sweep in its own PR |
| 9 | 🟡 | No unit test for the api_client stale-retry path (fix shipped, test wasn't) | Mock Dio adapter + Riverpod container; simulate 401 → epoch bump → assert retry rejected |

### Open — backend

| # | Sev | Bug | How to fix |
|---|-----|-----|------------|
| 10 | 🟠 | `python-jose` ≤3.5.0 algorithm-confusion advisory (CVE-2026-85394), **no patched release exists**. Not exploitable here (symmetric HS256, algorithms pinned) but permanently scanner-red | Migrate `security.py`'s ~3 call sites (encode/decode) to **PyJWT**; behaviour-identical for HS256 |
| 11 | 🟡 | Migration `0004_audit_fixes.py` `downgrade()` can violate the restored constraint / varchar(10) when newer-shaped rows exist | Add a data mapping in `downgrade()`, or declare it irreversible with a clear error |
| 12 | 🟡 | Ola directions + MSG91 OTP send are built to documented APIs but never exercised live (no keys in CI) | One manual smoke test with real keys; then recorded-response unit tests |
| 13 | 🟡 | Verify `ENVIRONMENT=production` actually refuses insecure defaults (placeholder `JWT_SECRET`, dev-OTP mode) as the env template promises | Assert at startup in `config.py`/`main.py`; add a pytest for it |
| 14 | ⚪ | Paid plans stay `pending` — no payment webhook | Intentional (v1.2); keep documented |

### Open — infra / process

| # | Sev | Bug | How to fix |
|---|-----|-----|------------|
| 15 | 🟡 | CI never builds an APK, so release-only failures (like the Java-25 one) surface at tag time | Add `flutter build apk --debug` as a CI job (per-PR on mobile/android changes, or nightly) |
| 16 | 🟡 | `LICENSE` is proprietary while the plan is a contributor community | Pick Apache-2.0 (or AGPL), add CONTRIBUTING.md, issue/PR templates, CoC, `good first issue` labels |
| 17 | ⚪ | v1.0.0 release build re-running with the Java-17 fix | Watcher reports when it lands; if green, apply drafted release notes |

## 2b. Security audit (authorized self-audit, 2026-11-18)

Full adversarial pass over backend + mobile. **Confirmed protections** (no
IDOR found: every trip-scoped router uses `require_trip_member`/`require_marshall`
with left-member exclusion and cross-checks `row.trip_id`; admin routers gated;
all raw SQL parameterized; JWT algorithms pinned + token types discriminated;
production preflight fails closed on default secret / dev-OTP / wildcard CORS;
OTP brute-force limits atomic + cooldown; uploads capped 25MB with random
names; list endpoints bounded; tokens in secure storage; no cleartext traffic
in release; billing can't self-grant Pro).

**Findings to fix** (severity-ordered):

| Sev | Finding | Where | Fix |
|---|---|---|---|
| High | WS identity spoofing — client `user_id`/`display_name`/`avatar_url` kept via `setdefault`, so a member can impersonate another in live location/chat fan-out | `app/ws/trips.py:179-184` | Hard-overwrite the identity fields from the authenticated socket user |
| High | Removed member keeps a live socket — membership checked only at connect | `app/ws/trips.py:88-90` | Re-check membership in the heartbeat; close socket on removal |
| High | Stored XSS via media upload — original extension kept, `/media` serves by extension (upload `.html`/`.svg` → JS on the API origin) | `app/routers/messages.py:342-345` + `main.py:173` | Extension/content-type allowlist + `nosniff` + `Content-Disposition: attachment` on `/media` |
| Med | Refresh tokens: no rotation/revocation/user check — a stolen 30-day token is perpetual | `app/routers/auth.py:167-181` | Redis JTI store: rotate on use, reject reuse, verify user exists |
| Med | WS token in query string → lands in proxy logs | `ws/trips.py:82`, `ws_client.dart:30` | First-message auth or `Sec-WebSocket-Protocol`; document log scrubbing |
| Med | No WS inbound frame-size/rate limits (Redis+DB amplification) | `ws/trips.py:173-202` | Per-connection token bucket + max frame size + drop unknown types |
| Med | slowapi keyed on direct peer IP — behind a reverse proxy all users share one bucket | `rate_limit.py:20` | `--proxy-headers` + `forwarded-allow-ips`; document in self-host guide |
| Med | `/media` unauthenticated & links never expire (mitigated by 128-bit names) | `main.py:173` | Later: signed URLs or authenticated media endpoint |
| Med | `/docs` + `/openapi.json` exposed in production | `main.py:107-112` | `docs_url=None`/`openapi_url=None` outside `local` |
| Low | Mute not enforced in voice/chat server-side; voice subgroup slug unchecked; `/trips/join` un-rate-limited (code brute force); client `attachment_url` stored verbatim (external tracking-pixel); OTP compare not constant-time; no security-headers middleware; livelink TTL ≤7d unrevocable | various (see audit) | Per-item one-liners; good community issues |
| Info | Real Ola key only in local untracked `env.dart` (not in git); restrict it by package on Ola's console | `lib/config/env.dart` | Key restriction on provider console |

## 3. Fix plan (ordered)

- **Phase 1 — ship now:** push #1/#2 (branch ready) → PR → merge; confirm #17
  (release) lands and publish the drafted notes.
- **Phase 2 — mobile correctness PR:** #3 (the 21 context-after-await sites),
  #4, #5, #6, #9, then the mechanical #8 sweep as a separate commit so review
  stays readable.
- **Phase 3 — security + backend hardening PR(s):** the three High security
  findings first (WS identity overwrite, removed-member socket closure, media
  upload allowlist + nosniff), then the Mediums (refresh rotation, WS limits,
  proxy-aware rate keys, docs off in prod), then #10 PyJWT migration, #11
  migration guard, #13 production-defaults test. (#13's fail-closed preflight
  was confirmed by the audit — keep a regression test anyway.)
- **Phase 4 — process & community:** #15 CI build job; #16 license +
  CONTRIBUTING + templates; file #7, #12, #14 (and any Phase-2/3 leftovers)
  as labelled GitHub issues — several are ideal `good first issue` seeds for
  the community push.
