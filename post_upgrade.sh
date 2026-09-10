#!/bin/sh

set -e

APP_INI="/usr/local/etc/gitea/conf/app.ini"
META_FILE="/root/.gitea_db_upgrade_meta"
STATUS_FILE="/root/status"
CURRENT_STEP="startup"
LAST_COMMAND="script entry"
LAST_RESULT="running"

write_status() {
    cat > "$STATUS_FILE" <<EOF
step=$CURRENT_STEP
last_command=$LAST_COMMAND
result=$LAST_RESULT
EOF
}

run_cmd() {
    step="$1"
    shift
    CURRENT_STEP="$step"
    LAST_COMMAND="$*"
    LAST_RESULT="running"
    write_status

    if "$@"; then
        rc=0
    else
        rc=$?
    fi

    LAST_RESULT="exit $rc"
    write_status

    if [ $rc -ne 0 ]; then
        exit $rc
    fi
}

run_eval() {
    step="$1"
    cmd="$2"
    CURRENT_STEP="$step"
    LAST_COMMAND="$cmd"
    LAST_RESULT="running"
    write_status

    if eval "$cmd"; then
        rc=0
    else
        rc=$?
    fi

    LAST_RESULT="exit $rc"
    write_status

    if [ $rc -ne 0 ]; then
        exit $rc
    fi
}

on_exit() {
    rc=$?
    if [ $rc -eq 0 ]; then
        LAST_RESULT="completed"
    elif [ "$LAST_RESULT" = "running" ]; then
        LAST_RESULT="failed with exit $rc"
    fi
    write_status
}

trap on_exit EXIT
write_status

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

run_psql_superuser() {
    psql -U postgres -v ON_ERROR_STOP=1 "$@"
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
    run_eval "enable postgresql rc" "sysrc postgresql_enable=YES >/dev/null"
    run_cmd "set tmp permissions" chmod 1777 /tmp

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
        run_cmd "initialize postgresql data" service postgresql initdb
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
            run_cmd "fix postgres data ownership" chown -R postgres:postgres "$PG_DATA_DIR"
        fi
    fi

    echo "Starting PostgreSQL service..."
    if ! service postgresql onestart; then
        echo "onestart failed, trying start..."
        run_cmd "start postgresql service" service postgresql start
    fi
    wait_for_service postgresql || {
        echo "ERROR: PostgreSQL failed to start. Cannot restore backup."
        exit 1
    }

    load_db_settings_from_app_ini

    # Restore the dump into the upgraded cluster using the same host/port/name/user settings
    # defined in Gitea's [database] section.
    echo "Restoring database dump..."
    run_eval "restore postgres dump" "psql -U postgres -v ON_ERROR_STOP=1 -d postgres -f \"$BACKUP_FILE\""

    # Ensure the role and database exist for the Gitea config in use.
    run_eval "check postgres role" "ROLE_EXISTS=\"\$(psql -U postgres -v ON_ERROR_STOP=1 -d template1 -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\" 2>/dev/null)\""
    if [ "$ROLE_EXISTS" != "1" ]; then
        run_eval "create postgres role" "psql -U postgres -v ON_ERROR_STOP=1 -d template1 -c \"CREATE USER ${DB_USER} CREATEDB;\""
    fi

    run_eval "check postgres database" "DB_EXISTS=\"\$(psql -U postgres -v ON_ERROR_STOP=1 -d template1 -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\" 2>/dev/null)\""
    if [ "$DB_EXISTS" != "1" ]; then
        run_eval "create postgres database" "psql -U postgres -v ON_ERROR_STOP=1 -d template1 -c \"CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER} TEMPLATE template0 ENCODING UTF8 LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';\""
    fi

    if [ -n "$DB_PASS" ]; then
        run_eval "set postgres password" "psql -U postgres -v ON_ERROR_STOP=1 -d template1 -c \"ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\""
    fi

    run_eval "ensure pg_trgm extension" "psql -U postgres -v ON_ERROR_STOP=1 -d \"${DB_NAME}\" -c \"CREATE EXTENSION IF NOT EXISTS pg_trgm;\""
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
run_cmd "disable gitea rc" sysrc gitea_enable=NO
run_cmd "disable gitea configcheck" sysrc gitea_configcheck_enable=NO
run_eval "stop gitea if running" "service gitea onestop >/dev/null 2>&1 || true"

# Set Permissions for config
echo "Setting permissions..."
run_cmd "set gitea conf ownership" chown -R git:git /usr/local/etc/gitea/conf
run_cmd "set gitea data ownership" chown -R git:git /usr/local/share/gitea
run_cmd "set tmp permissions" chmod 1777 /tmp

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
        run_cmd "initialize postgresql data" service postgresql initdb
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
            run_cmd "fix postgres data ownership" chown -R postgres:postgres "$PG_DATA_DIR"
        fi
        fi
    else
        echo "Warning: pg_ctl not found. PostgreSQL may not be installed."
    fi
fi
echo "Starting PostgreSQL service..."
if ! service postgresql onestart; then
    echo "onestart failed, trying start..."
    run_cmd "start postgresql service" service postgresql start
fi
wait_for_service postgresql || {
    echo "ERROR: PostgreSQL failed to start. Aborting upgrade."
    exit 1
}

# Start Gitea
echo "Starting Gitea service..."
run_cmd "enable gitea rc" sysrc gitea_enable=YES
run_eval "start gitea service" "service gitea start || echo \"Gitea may already be running\""
wait_for_service gitea

echo "Gitea upgrade complete!"
