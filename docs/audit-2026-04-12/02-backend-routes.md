# 02 — Backend routes

## Boot status

`from app.main import app` succeeds in a clean venv. **62 total routes** register, including 1 WebSocket and the FastAPI built-ins (`/openapi.json`, `/docs`, `/redoc`). Title: `PackPath API`.

## Routers registered (in `main.py` order)

| Router | File | Notes |
|---|---|---|
| health | `routers/health.py` | `GET /healthz` only |
| auth | `routers/auth.py` | OTP request/verify/refresh — phone-OTP |
| me | `routers/me.py` | `GET/PATCH /me` |
| trips | `routers/trips.py` | CRUD + join/leave/end + ghost mode |
| waypoints | `routers/waypoints.py` | list/create/delete (no reorder) |
| messages | `routers/messages.py` | list/post (REST) |
| directions | `routers/directions.py` | proxy + cost enrichment, two endpoints |
| etas | `routers/etas.py` | per-member ETA via maps resolver |
| maps | `routers/maps.py` | `GET /maps/providers` (no secrets) |
| devices | `routers/devices.py` | FCM token register/unregister |
| voice | `routers/voice.py` | LiveKit JWT mint with `?channel=` |
| safety | `routers/safety.py` | list / ack alerts |
| livelink | `routers/livelink.py` | mint + public read endpoint |
| group | `routers/group.py` | roles, ready-check, sub-groups, templates |
| expenses | `routers/expenses.py` | trip expenses + balances |
| privacy | `routers/privacy.py` | visibility scope, time-boxed share, audit log |
| recap | `routers/recap.py` | `GET /trips/{id}/recap` |
| reminders | `routers/reminders.py` | reminders CRUD + `calendar.ics` |
| events | `routers/events.py` | `POST /events` ingest |
| user_stats | `routers/user_stats.py` | `GET /me/stats` |
| billing | `routers/billing.py` | subscription stub create + list |
| admin_analytics | `routers/admin_analytics.py` | battery, provider health, ETA acc, ws lifetimes |
| admin_business | `routers/admin_business.py` | mrr, funnel, churn |
| ws/trips | `ws/trips.py` | `GET /ws/trips/{trip_id}` (WebSocket) |

## Placeholders / stubs found

- `routers/admin_analytics.py:125` — comment "placeholder rather than an error" in `eta_accuracy` (it depends on `events` rows that the mobile client doesn't write yet).
- `routers/billing.py:4` — module docstring openly says "stub immediately so we have data to". The actual Razorpay/Stripe webhooks are not wired.
- `routers/auth.py` — TODO comment in `request_otp` saying "integrate MSG91 send call here". When `MSG91_AUTH_KEY` is empty the OTP is returned in the API response (`otp_dev_mode`).

## SQLAlchemy models

`apps/backend/app/models/`: `audit.py`, `device.py`, `expense.py` (Expense + ExpenseShare), `message.py`, `reminder.py`, `safety.py`, `subgroup.py`, `subscription.py`, `trip.py` (Trip + TripMember), `user.py`, `waypoint.py`. All imported by `models/__init__.py`.

## Alembic migrations

- `versions/0001_initial.py` — users, trips, trip_members, waypoints (PostGIS GIST), messages, devices, locations TimescaleDB hypertable
- `versions/0002_advanced_features.py` — adds `safety_alerts`, `audit_logs`, `subgroups`, `expenses` + `expense_shares`, `subscriptions`, `reminders`, `events` (hypertable), `maps_provider_calls` (hypertable). Adds new columns to `trip_members` (`visibility_scope`, `share_until`, `is_ready`, `vehicle_label`, `subgroup_id`) and `trips` (`template`, `cover_color`).

Migration graph walks cleanly: `0001 → 0002`, single head.
