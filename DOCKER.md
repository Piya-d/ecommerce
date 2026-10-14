# Local Docker setup

Vanilla OroCommerce CE 7.0.4 (`oro/commerce-crm-application`) running in the same layout as `crm-application`: code, vendor and built assets are baked into one `php:8.5-apache` image, with no source bind mounts.

| Service | Purpose | Host port |
|---------|---------|-----------|
| `app` | Apache + PHP 8.5, `ORO_ENV=dev` | 8080 |
| `consumer` | `oro:message-queue:consume` (search index, images, mail) | — |
| `postgres` | PostgreSQL 17, DB `commerce`, `oro_user` / `oro_pass` | 5433 |
| `redis` | sessions (0), cache (1), doctrine (2), layout (3) | — |
| `gotenberg` | PDF generation | — |
| `mailcatcher` | catches outgoing mail | 1080 |

The ports are offset from crm-application (80 / 5432), so both stacks can run at the same time.

## First run

```bash
docker compose up -d --build      # image build takes 15-30 min
bin/docker-install.sh             # install with sample data, 20-40 min
```

- Storefront: http://localhost:8080/
- Back-office: http://localhost:8080/admin (`admin` / `admin`)
- Mail: http://localhost:1080

Until the install finishes, the `consumer` keeps restarting. That is expected.
Use `bin/docker-install.sh --no-sample-data` for an empty store.

## Persistence

| Volume | Holds |
|--------|-------|
| `postgres-data` | the database |
| `app-data` → `var/data` | attachments, product images, OAuth keys |
| `app-media` → `public/media` | resized images and generated media |

Everything else (cache, code, assets) comes from the image. After editing source, run:

```bash
docker compose build app && docker compose up -d
```

To reset everything, including the database: `docker compose down -v`.

## Helper scripts

Same as crm-application:

- `bin/oro-rebuild.sh [--env=dev|prod] [--no-migrations]`: full cache, migration and asset rebuild in the running container
- `bin/docker-refresh.sh [--purge-cache] [--migrations] ...`: lighter cache and asset refresh

Run a console command: `docker compose exec -u www-data app php bin/console <command>`
