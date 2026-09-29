#!/usr/bin/env bash
#
# Sets up the Cromberg PHP/MySQL companion service (server/) on a Debian or
# Ubuntu host: creates the database, applies every shipped migration in order,
# and writes Config.php from the example.
#
# It does NOT install Apache/PHP/MySQL for you and does NOT open any port.
#
# Usage:
#   DB_PASSWORD='...' ./deploy/setup-server.sh
#
# Environment (all optional except DB_PASSWORD):
#   DB_HOST      default: localhost
#   DB_NAME      default: cromberg
#   DB_USER      default: cromberg
#   DB_PASSWORD  required - no default, the script refuses to invent one
#   NOTIFY_KEY   shared secret guarding /notify; default: a generated value
#   DOMAIN       public hostname used in emails; default: localhost

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_DIR="$REPO_ROOT/server/db"
CONFIG="$REPO_ROOT/server/www/Cromberg/Config.php"
EXAMPLE="$REPO_ROOT/server/www/Cromberg/Config.php.example"

DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-cromberg}"
DB_USER="${DB_USER:-cromberg}"
DOMAIN="${DOMAIN:-localhost}"

if [[ -z "${DB_PASSWORD:-}" ]]; then
    echo "error: DB_PASSWORD is not set." >&2
    echo "Pick a real password; this script will not generate a database password for you." >&2
    exit 1
fi

NOTIFY_KEY="${NOTIFY_KEY:-$(head -c 24 /dev/urandom | base64)}"

echo "==> Creating database '$DB_NAME' and user '$DB_USER'"
mariadb -h "$DB_HOST" <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

# Migrations are date-prefixed (YYYY-MM-DD.N.sql); lexical sort is chronological.
# They must run in order: later files ALTER tables the earlier ones create.
echo "==> Applying migrations"
for f in $(ls "$DB_DIR"/*.sql | sort); do
    printf '    %-28s ' "$(basename "$f")"
    mariadb -h "$DB_HOST" "$DB_NAME" < "$f"
    echo "ok"
done

if [[ -f "$CONFIG" ]]; then
    echo "==> $CONFIG already exists, leaving it untouched"
else
    echo "==> Writing Config.php"
    sed -e "s|static \$db_host = 'localhost';|static \$db_host = '$DB_HOST';|" \
        -e "s|static \$db_name = '';|static \$db_name = '$DB_NAME';|" \
        -e "s|static \$db_user = '';|static \$db_user = '$DB_USER';|" \
        -e "s|static \$db_password = '';|static \$db_password = '$DB_PASSWORD';|" \
        -e "s|static \$notify_key = 'some random key';|static \$notify_key = '$NOTIFY_KEY';|" \
        -e "s|static \$domain_link = 'http://localhost';|static \$domain_link = 'https://$DOMAIN';|" \
        -e "s|static \$domain = 'localhost';|static \$domain = '$DOMAIN';|" \
        "$EXAMPLE" > "$CONFIG"
    chmod 640 "$CONFIG"
    echo "    notify key: $NOTIFY_KEY"
    echo "    (store it - the cron entry for /notify needs it)"
fi

echo
echo "Done. Config.php is gitignored upstream; keep it that way."
echo "Still to do by hand:"
echo "  - set \$exchangerate_key (api.exchangerate.host) for currency rates"
echo "  - point a vhost at server/www with the shipped .htaccess enabled"
echo "  - add the cron entries from server/crontab/config.md"
