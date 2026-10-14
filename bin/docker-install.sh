#!/usr/bin/env bash
#
# First-time install of OroCommerce inside the running Docker app container.
# Creates the schema, the admin user, the default website and loads the demo
# sample data (products, categories, customers, price lists, CMS pages).
#
# oro:install also re-runs oro:assets:install (JS routes, translations,
# locale data and webpack), so no separate asset step is needed afterwards.
#
# The database lives in the postgres-data volume, so this is needed once. To
# start over: docker compose down -v && docker compose up -d --build
#
# Usage: bin/docker-install.sh [options]
#   --no-sample-data     install an empty store
#   --url=URL            application URL (default: http://localhost:8080)
#   --admin-password=PW  admin password (default: admin)
#   -h, --help           show this help

set -euo pipefail

SERVICE="app"
APP_DIR="/var/www/html"
APP_ENV="dev"

sample_data="y"
app_url="http://localhost:8080"
admin_password="admin"

for arg in "$@"; do
    case "$arg" in
        --no-sample-data)   sample_data="n" ;;
        --url=*)            app_url="${arg#*=}" ;;
        --admin-password=*) admin_password="${arg#*=}" ;;
        -h|--help)          sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                  echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

cd "$(dirname "$0")/.."

if [ -z "$(docker compose ps -q "$SERVICE" 2>/dev/null)" ]; then
    echo "Service '$SERVICE' is not running. Start it with: docker compose up -d" >&2
    exit 1
fi

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

# Runs as www-data so cache and media files are owned by the Apache user and
# writable by the consumer, which also runs as www-data.
run() {
    docker compose exec -T -u www-data "$SERVICE" bash -c "cd $APP_DIR && $1"
}

# The consumer would otherwise start on queued messages against a half-built
# schema. It is started again once the install has finished.
step "Stopping consumer"
docker compose stop consumer

step "Installing OroCommerce (sample data: $sample_data). This takes 20-40 minutes."
run "php bin/console oro:install --env=$APP_ENV -n -vv \
    --timeout=0 \
    --skip-download-translations \
    --application-url='$app_url' \
    --organization-name='ORO' \
    --user-name=admin \
    --user-email=admin@example.com \
    --user-firstname=John \
    --user-lastname=Doe \
    --user-password='$admin_password' \
    --language=en \
    --formatting-code=en_US \
    --sample-data=$sample_data"

step "Starting consumer to index the storefront"
docker compose start consumer

printf '\n\033[1;32mDone.\033[0m\n'
printf '  Storefront:  %s/\n' "$app_url"
printf '  Back-office: %s/admin  (admin / %s)\n' "$app_url" "$admin_password"
printf '  Mail:        http://localhost:1080\n'
printf 'Storefront search fills in as the consumer works through the queue:\n'
printf '  docker compose logs -f consumer\n'
