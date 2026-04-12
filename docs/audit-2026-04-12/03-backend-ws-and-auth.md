# 03 — WebSocket fan-out + JWT enforcement

## WebSocket fan-out: ✅ real

Code path traced in `apps/backend/app/ws/trips.py`:

1. Client connects to `GET /ws/trips/{trip_id}?token=<JWT>`.
2. `_authenticate(token)` decodes the JWT and checks `claims["type"] == "access"`. Fails → close with `WS_1008_POLICY_VIOLATION`.
3. `_is_member(user_id, trip_id)` queries `trip_members` for an active row. Fails → close `WS_1008_POLICY_VIOLATION`.
4. On accept: `mark_online(trip_id, user_id)` adds the user to a Redis SET keyed `trip:{id}:online`.
5. `pubsub.subscribe(trip_channel(trip_id))` joins the per-trip channel `trip:{id}`.
6. Server publishes a `presence:joined` frame on the channel.
7. A background task `_pump_redis_to_ws` reads `pubsub.listen()` and forwards every Redis message to the WebSocket.
8. The main loop receives client frames, drops `location` frames if `_is_ghost(user_id, trip_id)` is true, calls `ingest_frame()` (persist + side effects), then `publish_trip(trip_id, frame)` and any returned `extras` (geofence arrival, safety alerts).
9. On disconnect: cancel the pump task, `mark_offline`, unsubscribe, publish `presence:left`.

`apps/backend/app/redis.py` exposes:

- `get_redis()` — singleton `redis.asyncio` client with `decode_responses=True`
- `trip_channel(trip_id) → "trip:{id}"`
- `trip_presence_key(trip_id) → "trip:{id}:online"` (used by FCM push to skip online users)
- `mark_online` / `mark_offline` / `online_user_ids`
- `publish_trip` / `subscribe_trip`

**Verdict:** Redis pub/sub fan-out is real, presence tracking is real, ghost-mode suppression is real. This works across multiple backend pods because subscription is per-pod and presence is in Redis.

## JWT enforcement: ✅ real

`apps/backend/app/deps.py` defines two dependencies that every protected route uses:

- `current_user` — reads `Authorization: Bearer <token>` header, calls `decode_token`, requires `claims["type"] == "access"`, looks up the `User` row by `sub`, raises 401 on any failure.
- `require_trip_member` — depends on `current_user`, then queries `trip_members` for the `(trip_id, user_id)` pair with `left_at IS NULL`, raises 403 if the user is not a member.

### Evidence of usage

Every router that handles user data uses one or both. Grep result on `routers/`:

```
trips.py: 8 usages (current_user + require_trip_member)
me.py: 2
waypoints.py: 3 (require_trip_member)
messages.py: 2
directions.py: 2 (require_trip_member)
etas.py: 1 (require_trip_member)
voice.py: 2
safety.py: 2 (require_trip_member)
livelink.py: 1 (require_trip_member to mint, but the public read uses a livelink JWT)
group.py: 7
expenses.py: 4
privacy.py: 4
reminders.py: 3 (require_trip_member)
recap.py: 1 (require_trip_member)
events.py: 1 (current_user only — needs improvement, see security file)
user_stats.py: 1
billing.py: 2
devices.py: 2
admin_analytics.py: 4 (current_user only — security gap, see security file)
admin_business.py: 3 (current_user only — security gap, see security file)
```

**Verdict:** The auth boundary is consistently enforced. Two real concerns are scoped in `04-backend-security.md`:
1. The `/admin/*` routes don't check an admin flag.
2. There's no rate limit on `/auth/otp/request`.

## Public livelink endpoint

`GET /public/livelink/{token}` is the only auth-free read endpoint. It validates a separate JWT type (`type=livelink`) signed with the same `JWT_SECRET`. Honors ghost mode in the response. Phone numbers are masked to `…XXXX`.
