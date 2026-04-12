# 04 — Backend security

Severity: 🔴 critical, 🟠 important, 🟡 worth fixing, 🟢 nit.

## 🔴 No rate limiting anywhere

Confirmed: `slowapi` / `fastapi-limiter` / any rate-limit package is **not** in `requirements.txt`. Grep against `apps/backend` returns zero matches for `RateLimit`, `slowapi`, `throttle`, etc. (the only matches are inside transitive dependency wheels).

Concrete attack surface:
- `POST /auth/otp/request` — accepts unlimited requests per phone, per IP, per anything. SMS-bombing victims, then SMS-cost-bombing your MSG91 account once it's wired.
- `POST /auth/otp/verify` — unlimited verify attempts, no lockout. 6-digit OTP → 10⁶ keyspace, brute-forceable in minutes if unthrottled.
- `POST /events` — unlimited write to the TimescaleDB hypertable. A malicious authenticated user can fill the disk.

**Fix:** add `slowapi` (or use FastAPI's `Depends`-based limiter), apply `5/min/phone` on OTP request, `5/5min/phone` on OTP verify, `100/min/user` on `/events`.

## 🟠 JWT secret defaults to a dev string

`apps/backend/app/config.py:23`:
```python
jwt_secret: str = "change-me-in-prod"
```

There is no startup check that fails if `JWT_SECRET` equals the default in a non-`local` environment. A misconfigured prod deploy would let anyone mint JWTs against `change-me-in-prod`.

**Fix:** in `lifespan()` or app factory, raise on `settings.environment != "local" and settings.jwt_secret == "change-me-in-prod"`.

## 🟠 OTP dev mode auto-engages with no warning

`apps/backend/app/config.py:62`:
```python
@property
def otp_dev_mode(self) -> bool:
    return not self.msg91_auth_key
```

If `MSG91_AUTH_KEY` is unset in *any* environment (including prod), `request_otp` returns the OTP code in the response body. There is no log line at boot warning that dev mode is on.

**Fix:** raise at boot when `environment != "local"` and dev mode is on.

## 🟠 Admin routes are not actually admin-gated

`apps/backend/app/routers/admin_analytics.py` and `admin_business.py` only depend on `current_user`. Any logged-in PackPath user can `GET /admin/analytics/maps_provider_health` and see provider error rates, or `GET /admin/business/mrr` and see total platform MRR.

There is no `is_admin` column on `users` and no `require_admin` dependency.

**Fix:** add `users.is_admin: bool` (default false), add `require_admin = Depends(...)`, gate the two `/admin/*` routers behind it.

## 🟠 OTP code is stored in Redis as plaintext

`apps/backend/app/routers/auth.py:43`:
```python
await get_redis().setex(_otp_key(payload.phone), _settings.otp_ttl_seconds, code)
```

Anyone with Redis read access (compromised infra, log leak) gets every active OTP. The TTL is only 5 minutes, but still.

**Fix:** store HMAC(secret, code), compare HMACs on verify.

## 🟠 Refresh tokens don't rotate

`POST /auth/refresh` mints a new access+refresh pair from a valid refresh token without invalidating the old refresh token. A leaked refresh token stays usable until natural expiry (30 days).

**Fix:** keep a `refresh_jti_blacklist` set in Redis with TTL = remaining lifetime; reject reuse.

## 🟠 CORS defaults to `["*"]` with `allow_credentials=True`

`apps/backend/app/main.py:60`:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

`*` plus credentials is rejected by browsers, so it's degenerate, but the *intent* is too loose. In prod we need an explicit allowlist.

**Fix:** error at boot if `cors_origins == ["*"] and environment != "local"`.

## 🟡 Phone number is not E.164-validated

`OtpRequest.phone: str = Field(min_length=8, max_length=20)` — accepts arbitrary 8–20 character strings. No country code validation.

**Fix:** use `pydantic-extra-types` `PhoneNumber` or a regex.

## 🟡 No request size limit

FastAPI defaults are generous. `POST /events` accepts up to 200 events per batch but no upper bound on body size.

## 🟡 No structured access log

We have loguru configured for app logs but not a per-request access log with `request_id`. Hard to investigate incidents.

## 🟢 No secret in source

Grep of `apps/backend/app` for `sk_live`, `pk_live`, `eyJ`, hardcoded long base64 strings — clean. The `change-me-in-prod` JWT secret is the only baked-in default.
