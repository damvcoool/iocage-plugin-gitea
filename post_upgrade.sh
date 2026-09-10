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

detect_pg_data_dir() {
    # Prefer explicit rc setting when present.
    data_dir="$(sysrc -n postgresql_data 2>/dev/null || true)"
    if [ -n "$data_dir" ] && [ -d "$data_dir" ]; then
        echo "$data_dir"
        return 0
    fi

    # Fallback to default FreeBSD PostgreSQL location.
    if [ -d /var/db/postgres ]; then
        find /var/db/postgres -maxdepth 1 -type d -name 'data*' 2>/dev/null | sort | tail -n 1
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
    touch /tmp/.gitea_pg_post_restore
    echo "Removed pre-upgrade backup artifacts."
}

load_db_settings_from_app_ini() {
    DB_HOST="$(read_ini_value "database" "HOST" || echo "127.0.0.1")"
    DB_PORT="5432"
    DB_USER="$(read_ini_value "database" "USER" || echo "gitea")"
    DB_NAME="$(read_ini_value "database" "NAME" || echo "gitea")"
    DB_PASS="$(read_ini_value "database" "PASSWD" || echo "")"

    case "$DB_HOST" in
        *:*)
            DB_PORT="${DB_HOST##*:}"
            DB_HOST="${DB_HOST%:*}"
            ;;
    esac
}

restore_postgresql_backup() {
    echo "Restoring PostgreSQL backup with upgraded PostgreSQL version..."
    sysrc postgresql_enable="YES" >/dev/null
    chmod 1777 /tmp

    # Ensure we have a valid data directory before attempting initdb
    PG_DATA_DIR="$(detect_pg_data_dir)"
    NEEDS_INITDB=false

    if ! service postgresql onestatus >/dev/null 2>&1; then
        NEEDS_INITDB=true
        echo "PostgreSQL service not running — initializing new data directory..."
    elif [ -z "$PG_DATA_DIR" ] || [ ! -d "$PG_DATA_DIR" ]; then
        NEEDS_INITDB=true
        echo "PostgreSQL data directory missing at $PG_DATA_DIR — initializing..."
    fi

    if [ "$NEEDS_INITDB" = true ]; then
        if ! service postgresql initdb; then
            echo "ERROR: PostgreSQL initdb failed. Cannot proceed without a valid data directory."
            echo "Investigate the error above and resolve manually."
            exit 1
        fi
        echo "PostgreSQL data directory initialized successfully."

        # Validate that the data directory exists and has correct ownership
        PG_DATA_DIR="$(detect_pg_data_dir)"
        if [ -z "$PG_DATA_DIR" ] || [ ! -d "$PG_DATA_DIR" ]; then
            echo "ERROR: Data directory was not created at expected location: $PG_DATA_DIR"
            echo "The package may use a different data directory path for this PostgreSQL version."
            echo "Please check pkg-message or /usr/local/etc/rc.d/postgresql for clues."
            exit 1
        fi

        # Verify ownership is postgres:postgres
        PG_OWNER="$(ls -ld "$PG_DATA_DIR" 2>/dev/null | awk '{print $3}')"
        if [ "$PG_OWNER" != "postgres" ]; then
            echo "ERROR: Data directory owned by '$PG_OWNER' instead of 'postgres'."
            echo "Fixing ownership by running chown postgres:postgres $PG_DATA_DIR"
            chown -R postgres:postgres "$PG_DATA_DIR"
        fi
    fi

    echo "Starting PostgreSQL service..."
    if ! service postgresql onestart; then
        echo "onestart failed, trying start..."
        service postgresql start
    fi
    wait_for_service postgresql || {
        echo "ERROR: PostgreSQL failed to start. Cannot restore backup."
        exit 1
    }

    load_db_settings_from_app_ini

    # Restore the dump into the upgraded cluster using the same host/port/name/user settings
    # defined in Gitea's [database] section.
    echo "Restoring database dump..."
    su -m postgres -c "psql -v ON_ERROR_STOP=1 -d postgres -f \"$BACKUP_FILE\""

    # Ensure the role and database exist for the Gitea config in use.
    ROLE_EXISTS="$(su -m postgres -c "psql -d template1 -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\"" 2>/dev/null)"
    if [ "$ROLE_EXISTS" != "1" ]; then
        su -m postgres -c "psql -d template1 -c \"CREATE USER ${DB_USER} CREATEDB;\""
    fi

    DB_EXISTS="$(su -m postgres -c "psql -d template1 -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\"" 2>/dev/null)"
    if [ "$DB_EXISTS" != "1" ]; then
        su -m postgres -c "psql -d template1 -c \"CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER} TEMPLATE template0 ENCODING UTF8 LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';\""
    fi

    if [ -n "$DB_PASS" ]; then
        su -m postgres -c "psql -d template1 -c \"ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\""
    fi

    su -m postgres -c "psql -d \"${DB_NAME}\" -c \"CREATE EXTENSION IF NOT EXISTS pg_trgm;\""
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
# On PostgreSQL upgrades the new cluster may not be initialized yet.
# Ensure the service is initialized before starting the upgraded instance.
echo "Starting PostgreSQL database..."
if ! service postgresql onestatus >/dev/null 2>&1; then
    echo "PostgreSQL service not running — initializing data directory..."
    # Only initdb if we know we have PostgreSQL installed and this is a fresh start
    if command -v pg_ctl >/dev/null 2>&1; then
        PG_DATA_DIR="$(detect_pg_data_dir)"
        if [ -n "$PG_DATA_DIR" ] && [ -d "$PG_DATA_DIR" ]; then
            echo "PostgreSQL data directory already exists at $PG_DATA_DIR"
        else
        if ! service postgresql initdb; then
            echo "ERROR: PostgreSQL initdb failed. Check logs at /var/log/messages for details."
            exit 1
        fi
        echo "PostgreSQL data directory initialized successfully."

        # Validate the data directory was created without requiring a running server
        PG_DATA_DIR="$(detect_pg_data_dir)"
        if [ -z "$PG_DATA_DIR" ] || [ ! -d "$PG_DATA_DIR" ]; then
            echo "ERROR: Data directory not found after initdb at $PG_DATA_DIR"
            echo "Check PostgreSQL version and cluster name configuration."
            exit 1
        fi

        # Ensure correct ownership
        PG_OWNER="$(ls -ld "$PG_DATA_DIR" 2>/dev/null | awk '{print $3}')"
        if [ "$PG_OWNER" != "postgres" ]; then
            echo "Fixing data directory ownership: $PG_DATA_DIR"
            chown -R postgres:postgres "$PG_DATA_DIR"
        fi
        fi
    else
        echo "Warning: pg_ctl not found. PostgreSQL may not be installed."
    fi
fi
echo "Starting PostgreSQL service..."
if ! service postgresql onestart; then
    echo "onestart failed, trying start..."
    service postgresql start
fi
wait_for_service postgresql || {
    echo "ERROR: PostgreSQL failed to start. Aborting upgrade."
    exit 1
}

# Start Gitea
echo "Starting Gitea service..."
service gitea start || echo "Gitea may already be running"
wait_for_service gitea

echo "Gitea upgrade complete!"
