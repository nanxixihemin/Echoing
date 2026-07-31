# Echoing backend deployment

The backend uses Python 3, SQLite, and the packages pinned in
`backend/requirements.txt` for RSA/PSS JWT verification.

## Suggested server layout

```text
/opt/echoing/backend
/opt/echoing/venv
/opt/echoing/backend/data
```

Copy `backend/` to `/opt/echoing/backend`, then create `/opt/echoing/backend/.env` from `deploy/echoing.env.example`.

Use a strong `ADMIN_PASSWORD` before the first boot. The backend creates the first admin user only when the admin table is empty.

Confirm the existing server-side `ECHOING_DB_PATH` before deployment and keep
that path unless you intentionally migrate the database. The current production
layout uses:

```text
ECHOING_DB_PATH=/opt/echoing/backend/data/echoing.db
```

Do not replace the server `.env` during redeploy unless you have reviewed every
value. In particular, preserve `MODELSCOPE_API_KEY`, `ADMIN_PASSWORD`, and
`ECHOING_DB_PATH`.

## Pre-deploy checks

Run locally before uploading:

```powershell
cd backend
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
cd ..
python -m compileall backend
$env:DEVECO_SDK_HOME='D:\Dev\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Dev\DevEco Studio\jbr'
node 'D:\Dev\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
```

Check the target server before changing files:

```bash
curl https://echoing.negentropypixels.me/health
sudo systemctl status echoing-backend --no-pager
```

Back up the active SQLite database first:

```bash
sudo mkdir -p /var/backups/echoing
sudo cp /opt/echoing/backend/data/echoing.db /var/backups/echoing/echoing.$(date +%Y%m%d-%H%M%S).db
```

If an older server was explicitly configured with `/var/lib/echoing/echoing.db`,
back up that file instead and preserve the existing path during redeploy. Confirm
the active path from the server-side `ECHOING_DB_PATH` environment setting; do
not switch paths merely because the example file changed. The current public
health endpoint intentionally does not expose the database path.

## systemd

```bash
sudo useradd --system --home /opt/echoing --shell /usr/sbin/nologin echoing
sudo mkdir -p /opt/echoing/backend/data
sudo chown -R echoing:echoing /opt/echoing
sudo -u echoing python3 -m venv /opt/echoing/venv
sudo -u echoing /opt/echoing/venv/bin/python -m pip install --upgrade pip
sudo -u echoing /opt/echoing/venv/bin/python -m pip install -r /opt/echoing/backend/requirements.txt
sudo chmod 600 /opt/echoing/backend/.env
sudo cp deploy/echoing-backend.service /etc/systemd/system/echoing-backend.service
sudo systemctl daemon-reload
sudo systemctl enable --now echoing-backend
sudo systemctl status echoing-backend --no-pager
```

The unit deliberately starts `/opt/echoing/venv/bin/python`; install dependencies
into that same virtual environment. Installing with `python3 -m pip --user` while
starting `/usr/bin/python3` is not reliable for a system user with a nologin home.

## Redeploy existing backend

For an existing server, stop the service, upload only backend code changes, keep
`.env` and `data/` on the server, then restart:

```bash
sudo systemctl stop echoing-backend

# Upload/replace backend source files under /opt/echoing/backend.
# Preserve these server-side files/directories:
# - /opt/echoing/backend/.env
# - /opt/echoing/backend/data/

sudo -u echoing /opt/echoing/venv/bin/python -m pip install -r /opt/echoing/backend/requirements.txt
sudo chown -R echoing:echoing /opt/echoing/backend
sudo chmod 600 /opt/echoing/backend/.env
sudo systemctl daemon-reload
sudo systemctl start echoing-backend
sudo systemctl status echoing-backend --no-pager
curl https://echoing.negentropypixels.me/health
curl https://echoing.negentropypixels.me/api/leaves
```

The SQLite migrations run automatically when the backend starts. The new
authentication migration is additive and keeps old rows compatible. Deploy in
this order: back up SQLite, install Python dependencies, update backend code,
add provider environment values, restart the backend, verify public and auth
endpoints, then build and distribute the new HarmonyOS app. The old app cannot
use private APIs after the backend begins requiring App Bearer tokens.

Required new production settings are `AGC_PROJECT_ID`, `AGC_TOKEN_ISSUER`, and
`HUAWEI_ACCOUNT_CLIENT_ID`. Keep the official AGC key URL and Huawei OIDC
discovery/issuer defaults unless Huawei's console documentation for this app
requires a regional endpoint. A missing or invalid provider setting disables
that login path safely.

## Authentication verification

Use placeholders only:

```bash
curl -X POST https://echoing.negentropypixels.me/api/app-auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"provider":"agc","credential":"<AGC_ACCESS_TOKEN>","deviceId":"<DEVICE_ID>"}'

curl https://echoing.negentropypixels.me/api/app-auth/me \
  -H 'Authorization: Bearer <ECHOING_ACCESS_TOKEN>'

curl -X POST https://echoing.negentropypixels.me/api/app-auth/refresh \
  -H 'Content-Type: application/json' \
  -d '{"refreshToken":"<ECHOING_REFRESH_TOKEN>","deviceId":"<DEVICE_ID>"}'
```

## Rollback

Keep the previous backend source release beside the new release. If application
verification fails, stop the service, restore the previous source, keep the
current `.env` and SQLite file, reinstall that release's requirements, and
restart:

```bash
sudo systemctl stop echoing-backend
sudo rsync -a --delete --exclude .env --exclude data/ /opt/echoing/releases/<PREVIOUS_RELEASE>/ /opt/echoing/backend/
sudo -u echoing /opt/echoing/venv/bin/python -m pip install -r /opt/echoing/backend/requirements.txt
sudo systemctl start echoing-backend
sudo systemctl status echoing-backend --no-pager
curl https://echoing.negentropypixels.me/health
```

Do not roll back or delete migration 005 tables. They are additive and older
code ignores them. Restore the pre-deploy SQLite backup only for confirmed data
corruption, because doing so discards sessions and writes created after backup.

## nginx

The nginx template is configured for `echoing.negentropypixels.me`. It redirects
domain HTTP traffic to HTTPS, rejects direct plaintext IP access, and proxies
HTTPS traffic to the backend on loopback port `8111`. The HTTPS server also adds
HSTS, MIME-sniffing, frame, and referrer security headers.

Issue the certificate with the webroot authenticator before installing the
final nginx configuration:

```bash
sudo mkdir -p /var/www/html/.well-known/acme-challenge
sudo certbot certonly --webroot --webroot-path /var/www/html \
  -d echoing.negentropypixels.me
```

Then install and validate the configuration:

```bash
sudo cp deploy/nginx-echoing.conf /etc/nginx/sites-available/echoing
sudo nginx -t
sudo systemctl reload nginx
sudo certbot renew --dry-run
```

The admin panel is available at
`https://echoing.negentropypixels.me/admin`.
