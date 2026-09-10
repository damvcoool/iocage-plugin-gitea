#!/bin/sh

set -e

APP_INI="/usr/local/etc/gitea/conf/app.ini"
META_FILE="/root/.gitea_db_upgrade_meta"
BACKUP_FILE="/root/gitea_pg_backup.sql"

read_ini_value() {
    section="$1"
    key="$2"
    if [ ! -f "$APP_INI" ]; then
        return 1
    fi

    awk -F '=' -v section="$section" -v key="$key" '
        function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            current = trim(substr($0, 2, length($0) - 2))
            next
        }
        current == section {
            if (index($0, "=") > 0) {
                k = trim(substr($0, 1, index($0, "=") - 1))
                v = trim(substr($0, index($0, "=") + 1))
                gsub(/"/, "", v)
                if (toupper(k) == toupper(key)) {
                    print v
                    exit
                }
            }
        }
    ' "$APP_INI" 2>/dev/null | head -n 1
}

detect_db_type() {
    if [ -f "$APP_INI" ]; then
        value="$(read_ini_value "database" "DB_TYPE")"
        if [ -n "$value" ]; then
            printf '%s\n' "$value" | tr '[:upper:]' '[:lower:]' | head -n 1
        fi
    fi
}

detect_pg_version() {
    if command -v psql >/dev/null 2>&1; then
        psql --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\).*/\1/p' | head -n 1
    fi
}

DB_TYPE="$(detect_db_type)"
[ -n "$DB_TYPE" ] || DB_TYPE="unknown"

case "$DB_TYPE" in
    postgres|postgresql|pgsql)
        DB_PROGRAM="postgresql"
        ;;
    *)
        DB_PROGRAM="$DB_TYPE"
        ;;
esac

DB_VERSION=""
if [ "$DB_PROGRAM" = "postgresql" ]; then
    DB_VERSION="$(detect_pg_version)"
fi

cat > "$META_FILE" <<EOF
RECORDED_DB_TYPE=$DB_TYPE
RECORDED_DB_PROGRAM=$DB_PROGRAM
RECORDED_DB_VERSION=$DB_VERSION
BACKUP_FILE=$BACKUP_FILE
EOF

if [ "$DB_PROGRAM" != "postgresql" ]; then
    echo "Database program '$DB_PROGRAM' does not require PostgreSQL pre-upgrade backup."
    exit 0
fi

echo "Creating PostgreSQL backup before upgrade..."
# Do not initdb before an upgrade. The existing database must remain active until the
# upgraded PostgreSQL service is running and the data is restored into the new cluster.
service postgresql onestatus >/dev/null 2>&1 || service postgresql onestart
su -m postgres -c "pg_dumpall -f $BACKUP_FILE"
chmod 600 "$BACKUP_FILE"
echo "PostgreSQL backup saved to $BACKUP_FILE"
