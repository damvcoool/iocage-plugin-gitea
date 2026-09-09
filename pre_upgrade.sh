#!/bin/sh

set -e

APP_INI="/usr/local/etc/gitea/conf/app.ini"
META_FILE="/root/.gitea_db_upgrade_meta"
BACKUP_FILE="/root/gitea_pg_backup.sql"

detect_db_type() {
    if [ -f "$APP_INI" ]; then
        awk -F '=' '
            /^[[:space:]]*DB_TYPE[[:space:]]*=/ {
                value=$2
                gsub(/[[:space:]]/, "", value)
                gsub(/"/, "", value)
                print tolower(value)
                exit
            }
        ' "$APP_INI"
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
service postgresql onestatus >/dev/null 2>&1 || service postgresql onestart
su -m postgres -c "pg_dumpall -f $BACKUP_FILE"
chmod 600 "$BACKUP_FILE"
echo "PostgreSQL backup saved to $BACKUP_FILE"
