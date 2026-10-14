#!/usr/bin/env bash
#
# Full Oro rebuild inside the running Docker app container, in order:
#   1. remove the cache folder
#   2. clear cache
#   3. run migrations
#   4. install assets
#   5. build assets
#   6. dump JS routing
#   7. dump translations
#   8. clear cache again
#
# NOTE: docker-compose.yml mounts no source volumes, so this operates on the
# code baked into the image. After changing source files you must rebuild:
#     docker compose build app && docker compose up -d app
#
# Usage: bin/oro-rebuild.sh [--env=dev|prod] [--no-migrations]

set -euo pipefail

SERVICE="app"
APP_DIR="/var/www/html"
APP_ENV="dev"
run_migrations=true

for arg in "$@"; do
    case "$arg" in
        --env=*)         APP_ENV="${arg#*=}" ;;
        --no-migrations) run_migrations=false ;;
        -h|--help)       sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

cd "$(dirname "$0")/.."

if [ -z "$(docker compose ps -q "$SERVICE" 2>/dev/null)" ]; then
    echo "Service '$SERVICE' is not running. Start it with: docker compose up -d $SERVICE" >&2
    exit 1
fi

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
run()  { docker compose exec -T "$SERVICE" bash -c "cd $APP_DIR && $1"; }

# Only var/cache is removed. var/ itself also holds data, sessions,
# attachments and maintenance, which must survive.
step "1/8 Removing cache folder"
run "rm -rf var/cache/* && mkdir -p var/cache"

# --no-warmup because warmup queries the DB with the current entity mappings,
# which fail if migrations (step 3) have not been applied yet. Step 8 does the
# full warmup once the schema is up to date.
step "2/8 Clearing cache ($APP_ENV)"
run "bin/console cache:clear --no-warmup --env=$APP_ENV"

if [ "$run_migrations" = true ]; then
    step "3/8 Running migrations"
    run "bin/console oro:migration:load --force --env=$APP_ENV"
else
    step "3/8 Migrations skipped (--no-migrations)"
fi

step "4/8 Installing assets"
run "bin/console assets:install --env=$APP_ENV"

step "5/8 Building assets"
run "bin/console oro:assets:build --env=$APP_ENV"

step "6/8 Dumping JS routing"
run "bin/console fos:js-routing:dump --env=$APP_ENV"

step "7/8 Dumping translations"
run "bin/console oro:translation:dump --env=$APP_ENV"
run "bin/console oro:localization:dump --env=$APP_ENV"

step "8/8 Clearing cache again"
run "bin/console cache:clear --env=$APP_ENV"

# Console commands run as root; Apache serves as www-data.
run "chown -R www-data:www-data var public"

printf '\n\033[1;32mDone.\033[0m\n'
