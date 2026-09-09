#!/bin/sh

set -e

APP_INI="/usr/local/etc/gitea/conf/app.ini"
META_FILE="/root/.gitea_db_upgrade_meta"

# Function to wait for service to be running
wait_for_service() {
    service_name="$1"
    max_attempts=30
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if service "$service_name" status >/dev/null 2>&1; then
            echo "$service_name is running"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    echo "Warning: $service_name did not start within expected time"
    return 1
}

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

normalize_db_program() {
    case "$1" in
        postgres|postgresql|pgsql)
            echo "postgresql"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

cleanup_backup() {
    rm -f "$BACKUP_FILE" "$META_FILE"
    echo "Removed pre-upgrade backup artifacts."
}

restore_postgresql_backup() {
    echo "Restoring PostgreSQL backup with upgraded PostgreSQL version..."
    sysrc postgresql_enable=YES >/dev/null
    chmod 1777 /tmp
    service postgresql initdb || true
    service postgresql onestart || service postgresql start || true
    wait_for_service postgresql
    su -m postgres -c "psql -v ON_ERROR_STOP=1 -f $BACKUP_FILE postgres"
    cleanup_backup
}

if [ -f "$META_FILE" ]; then
    . "$META_FILE"

    RECORDED_DB_PROGRAM="$(normalize_db_program "$RECORDED_DB_PROGRAM")"
    CURRENT_DB_TYPE="$(detect_db_type)"
    [ -n "$CURRENT_DB_TYPE" ] || CURRENT_DB_TYPE="unknown"
    CURRENT_DB_PROGRAM="$(normalize_db_program "$CURRENT_DB_TYPE")"

    CURRENT_DB_VERSION=""
    if [ "$CURRENT_DB_PROGRAM" = "postgresql" ]; then
        CURRENT_DB_VERSION="$(detect_pg_version)"
    fi

    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        if [ "$RECORDED_DB_PROGRAM" = "$CURRENT_DB_PROGRAM" ] &&
            [ "$RECORDED_DB_VERSION" = "$CURRENT_DB_VERSION" ]; then
            echo "Database program and version unchanged ($CURRENT_DB_PROGRAM $CURRENT_DB_VERSION)."
            echo "Keeping existing database and clearing backup."
            cleanup_backup
        elif [ "$RECORDED_DB_PROGRAM" = "postgresql" ] &&
            [ "$CURRENT_DB_PROGRAM" = "postgresql" ]; then
            restore_postgresql_backup
        else
            echo "Database program changed from '$RECORDED_DB_PROGRAM' to '$CURRENT_DB_PROGRAM'."
            echo "Skipping automatic restore and keeping backup at $BACKUP_FILE for manual handling."
        fi
    else
        rm -f "$META_FILE"
    fi
fi

echo "Upgrading Gitea plugin..."

# Check existing config before starting
echo "Configuring Gitea service..."
sysrc gitea_configcheck_enable=NO

# Set Permissions for config
echo "Setting permissions..."
chown -R git:git /usr/local/etc/gitea/conf
chown -R git:git /usr/local/share/gitea
chmod 1777 /tmp

# Start Database
echo "Starting PostgreSQL database..."
service postgresql start || echo "PostgreSQL may already be running"
wait_for_service postgresql

# Start Gitea
echo "Starting Gitea service..."
service gitea start || echo "Gitea may already be running"
wait_for_service gitea

echo "Gitea upgrade complete!"
