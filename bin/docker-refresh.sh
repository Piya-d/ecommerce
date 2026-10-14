#!/usr/bin/env bash
#
# Rebuild caches and assets inside the running Docker app container.
#
# NOTE: docker-compose.yml mounts no source volumes, so everything this script
# does lives only in the running container. It survives `docker compose restart`
# but is LOST on `docker compose up -d` after an image rebuild, which recreates
# the container from the image. For a permanent change, rebuild the image:
#     docker compose build app && docker compose up -d app
#
# Usage: bin/docker-refresh.sh [options]
#   --purge-cache    delete var/cache contents before clearing (hard reset)
#   --prod           also clear the prod cache
#   --entity-config  clear extended-entity cache and update entity config
#   --migrations     run pending migrations (writes to the database)
#   --dry-run        list pending migrations without applying them
#   -h, --help       show this help

set -euo pipefail

SERVICE="app"
APP_DIR="/var/www/html"
APP_ENV="dev"

purge_cache=false
do_prod=false
do_entity_config=false
do_migrations=false
do_dry_run=false

while [ $# -gt 0 ]; do
    case "$1" in
        --purge-cache)   purge_cache=true ;;
        --prod)          do_prod=true ;;
        --entity-config) do_entity_config=true ;;
        --migrations)    do_migrations=true ;;
        --dry-run)       do_dry_run=true ;;
        -h|--help)       sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

cd "$(dirname "$0")/.."

if [ -z "$(docker compose ps -q "$SERVICE" 2>/dev/null)" ]; then
    echo "Service '$SERVICE' is not running. Start it with: docker compose up -d $SERVICE" >&2
    exit 1
fi

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

run() {
    docker compose exec -T "$SERVICE" bash -c "cd $APP_DIR && $1"
}

# Only var/cache is purged. Never delete var/ itself: it also holds var/data,
# var/sessions, var/attachments and var/maintenance.
if [ "$purge_cache" = true ]; then
    step "Purging var/cache"
    run "rm -rf var/cache/* && mkdir -p var/cache"
fi

step "Clearing $APP_ENV cache"
run "bin/console cache:clear --env=$APP_ENV"

step "Installing bundle assets"
run "bin/console assets:install --env=$APP_ENV"

step "Building webpack assets"
run "bin/console oro:assets:build --env=$APP_ENV"

step "Dumping JS routes"
run "bin/console fos:js-routing:dump --env=$APP_ENV"

step "Dumping JS translations"
run "bin/console oro:translation:dump --env=$APP_ENV"

# Generates public/js/oro.locale_data.js. oro:assets:install runs this as part
# of its chain; it is listed separately here because the steps above call
# assets:install and oro:assets:build directly.
step "Dumping locale data"
run "bin/console oro:localization:dump --env=$APP_ENV"

if [ "$do_dry_run" = true ]; then
    step "Pending migrations (dry run)"
    run "bin/console oro:migration:load --dry-run --env=$APP_ENV"
fi

if [ "$do_migrations" = true ]; then
    step "Loading migrations"
    run "bin/console oro:migration:load --force --env=$APP_ENV"
fi

if [ "$do_entity_config" = true ]; then
    step "Clearing extended entity cache"
    run "bin/console oro:entity-extend:cache:clear --env=$APP_ENV"
    step "Updating entity config"
    run "bin/console oro:entity-config:update --env=$APP_ENV"
fi

if [ "$do_prod" = true ]; then
    step "Clearing prod cache"
    run "bin/console cache:clear --env=prod"
fi

# Equivalent of `chmod -R 777 /websites`: the container runs Apache as
# www-data, and console commands above run as root, so writable paths need
# their ownership restored.
step "Restoring ownership"
run "chown -R www-data:www-data var public"

printf '\n\033[1;32mDone.\033[0m\n'
