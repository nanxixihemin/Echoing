# Echoing Backend

The Echoing backend is a Python HTTP service backed by SQLite. App users and
administrators use separate authentication systems.

## Authentication model

App login follows this chain:

```text
AGC email access token or Huawei Account authorization code
-> POST /api/app-auth/exchange
-> server-side Huawei code redemption, signature and claim verification
-> opaque Echoing access and refresh tokens
-> Authorization: Bearer <echoing_access_token>
```

Echoing access tokens expire after 30 minutes. Refresh tokens expire after 30
days and rotate on every refresh. Only SHA-256 token hashes are stored in
SQLite. Client-supplied `accountKey`, `userId`, `X-Account-Key`, and
`X-User-Id` never establish identity.

AGC verification follows Huawei's official Auth Server SDK behavior: it
verifies asymmetric JWT signatures with the official AGC public-key endpoint,
then validates issuer, project audience, issue time, and expiry. Huawei Account
login sends only a single-use authorization code from the device; the backend
exchanges it for an ID token at the discovered `token_endpoint` using the
confidential client secret, then validates signature, issuer, audience, expiry,
issue time, nonce, and `azp` when present via OpenID Connect discovery and
JWKS. Both providers fail closed.

## Install and configure

```powershell
cd backend
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Required provider values:

- `AGC_PROJECT_ID`: AGC project/product identifier expected in `aud`.
- `AGC_TOKEN_ISSUER`: expected AGC issuer, normally ending in the same project ID.
- `HUAWEI_ACCOUNT_CLIENT_ID`: Account Kit client ID expected in `aud` and `azp`.
  This is the AGC app ID, the same value declared as `client_id` in the client's
  `module.json5` metadata.
- `HUAWEI_ACCOUNT_CLIENT_SECRET`: Account Kit client secret used to redeem the
  authorization code. Server side only; it must never reach the client.
- `HUAWEI_ACCOUNT_REDIRECT_URI`: leave empty for on-device Account Kit login.
  Set it only if the AGC console requires a redirect URI on the token request.

The official HTTPS endpoints are configurable for controlled key rotation and
regional changes. Do not replace them with non-Huawei endpoints. Provider
verification timeout and clock skew are bounded by the backend.

AI rate limits default to 20 requests per user and 60 requests per IP in a
60-second window. The AI endpoint also limits body size, message count, message
length, and `max_tokens`; the model remains server-controlled.

Never commit `.env`. Keep `MODELSCOPE_API_KEY`, admin credentials, Huawei
secrets, tokens, signing data, and production databases out of source control.

## Run and test

```powershell
cd backend
python server.py
```

```powershell
cd backend
python -m unittest discover -s tests -v
python -m compileall .
```

Tests use temporary SQLite databases and provider-verifier test doubles. They
do not use production credentials or databases.

## APIs

Public:

```text
GET  /health
GET  /api/leaves
POST /api/leaves/{id}/like
```

App authentication:

```text
POST /api/app-auth/exchange
POST /api/app-auth/refresh
GET  /api/app-auth/me
POST /api/app-auth/logout
```

App Bearer token required:

```text
POST   /api/app-users/upsert
GET    /api/sessions
POST   /api/sessions
GET    /api/sessions/{id}
DELETE /api/sessions/{id}
GET    /api/memory-context
POST   /api/leaves
POST   /v1/chat/completions
```

HTTPS verification examples:

```bash
curl https://echoing.negentropypixels.me/health
curl https://echoing.negentropypixels.me/api/leaves
curl -X POST https://echoing.negentropypixels.me/api/app-auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"provider":"agc","credential":"<AGC_ACCESS_TOKEN>","deviceId":"<DEVICE_ID>"}'
curl -X POST https://echoing.negentropypixels.me/api/app-auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"provider":"huawei","credential":"<HUAWEI_AUTHORIZATION_CODE>","deviceId":"<DEVICE_ID>","nonce":"<LOGIN_NONCE>"}'
curl https://echoing.negentropypixels.me/api/app-auth/me \
  -H 'Authorization: Bearer <ECHOING_ACCESS_TOKEN>'
curl -X POST https://echoing.negentropypixels.me/api/app-auth/refresh \
  -H 'Content-Type: application/json' \
  -d '{"refreshToken":"<ECHOING_REFRESH_TOKEN>","deviceId":"<DEVICE_ID>"}'
```

Admin endpoints remain under `/api/auth/*` and `/api/admin/*`. Admin tokens are
not valid for App APIs, and App tokens are not valid for admin APIs.

## Database migration

Migration 005 adds:

- `app_identities`
- `app_auth_sessions`
- `app_identity_migrations`

The migration is additive and idempotent. Existing `app_users`, sessions,
leaves, and AI history remain in place. A legacy `email_<normalized email>` user
is linked only after AGC supplies the same verified email and the legacy user
has not already been linked. Legacy Huawei `openID` rows are never auto-linked.
Migration audit rows contain a hash of the legacy account key, never a token.

Run `python server.py` to apply pending migrations automatically. Back up the
SQLite file first in production. See `deploy/README.md` for deployment and
rollback steps.
