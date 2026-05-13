# Echoing backend deployment

This deployment path keeps the backend dependency-free: Python 3 standard library plus SQLite.

## Suggested server layout

```text
/opt/echoing/backend
/var/lib/echoing
```

Copy `backend/` to `/opt/echoing/backend`, then create `/opt/echoing/backend/.env` from `deploy/echoing.env.example`.

Use a strong `ADMIN_PASSWORD` before the first boot. The backend creates the first admin user only when the admin table is empty.

## systemd

```bash
sudo useradd --system --home /opt/echoing --shell /usr/sbin/nologin echoing
sudo mkdir -p /opt/echoing /var/lib/echoing
sudo chown -R echoing:echoing /opt/echoing /var/lib/echoing
sudo cp deploy/echoing-backend.service /etc/systemd/system/echoing-backend.service
sudo systemctl daemon-reload
sudo systemctl enable --now echoing-backend
sudo systemctl status echoing-backend
```

## nginx

Copy `deploy/nginx-echoing.conf` to your nginx site directory, replace `example.com`, then reload nginx.

```bash
sudo nginx -t
sudo systemctl reload nginx
```

The admin panel is available at `/admin`.
