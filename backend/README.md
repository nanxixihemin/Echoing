# Echoing Backend

Echoing backend is intentionally small: Python standard library, SQLite, no web framework dependency.

It provides:

- ModelScope chat-completions proxy
- Shared forest persistence
- Admin login and bearer-token auth
- Admin panel
- Leaf moderation and deletion
- AI request history
- SQLite schema migrations

## Configure

Create `backend/.env` from `.env.example`.

```env
MODELSCOPE_API_KEY=replace_with_modelscope_api_key
MODELSCOPE_API_BASE=https://api-inference.modelscope.cn/v1
MODELSCOPE_MODEL=deepseek-ai/DeepSeek-V4-Flash
HOST=0.0.0.0
PORT=8111
ECHOING_DB_PATH=./data/echoing.db
ADMIN_USERNAME=admin
ADMIN_PASSWORD=replace_with_strong_admin_password
AUTH_TOKEN_TTL_HOURS=24
MODERATION_BLOCK_KEYWORDS=
```

Do not commit `backend/.env`. Change `ADMIN_PASSWORD` before deployment.

The first admin user is created automatically on startup when the `admin_users` table is empty.

## Run

```powershell
cd backend
python server.py
```

Health check:

```text
http://127.0.0.1:8111/health
```

Admin panel:

```text
http://127.0.0.1:8111/admin
```

## Public APIs

List shared leaves:

```powershell
Invoke-WebRequest -Uri http://127.0.0.1:8111/api/leaves
```

Create a leaf:

```powershell
Invoke-WebRequest -Uri http://127.0.0.1:8111/api/leaves -Method POST -ContentType 'application/json' -Body '{"content":"hello","nickname":"anonymous"}'
```

Like a leaf:

```powershell
Invoke-WebRequest -Uri http://127.0.0.1:8111/api/leaves/<leaf_id>/like -Method POST
```

AI proxy:

```text
POST /v1/chat/completions
```

The backend always uses `MODELSCOPE_MODEL` from `.env`; the app cannot override the model.

## Admin APIs

Login:

```text
POST /api/auth/login
```

Use the returned token as:

```text
Authorization: Bearer <token>
```

Admin-only endpoints:

```text
GET    /api/auth/me
POST   /api/auth/logout
GET    /api/admin/leaves
DELETE /api/admin/leaves/<leaf_id>
POST   /api/admin/leaves/<leaf_id>/hide
POST   /api/admin/leaves/<leaf_id>/restore
GET    /api/admin/ai-history
```

For compatibility, this also works as an admin-only delete endpoint:

```text
DELETE /api/leaves/<leaf_id>
```

## SQLite

The database is initialized and migrated automatically on startup.

Tables:

- `schema_migrations`
- `shared_leaves`
- `admin_users`
- `auth_sessions`
- `ai_history`

Shared leaves are kept visible for 7 days. Expired leaves are soft-deleted when the list endpoint is called.

API keys are never stored in SQLite.

## Deployment

See `deploy/README.md` for systemd and nginx templates.
