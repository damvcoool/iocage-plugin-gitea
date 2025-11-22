#!/bin/sh
# Gitea Backup and Restore Script
# This script helps backup and restore Gitea data and database

set -e

BACKUP_DIR="/root/gitea-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="gitea-backup-${TIMESTAMP}"

print_usage() {
    cat <<EOF
Usage: $0 [backup|restore|list]

Commands:
  backup   - Create a backup of Gitea data and PostgreSQL database
  restore  - Restore from a specific backup
  list     - List available backups

Examples:
  $0 backup
  $0 restore gitea-backup-20240101-120000
  $0 list
EOF
}

backup_gitea() {
    echo "=========================================="
    echo "Starting Gitea Backup"
    echo "=========================================="
    
    # Create backup directory if it doesn't exist
    mkdir -p "${BACKUP_DIR}"
    
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
    mkdir -p "${BACKUP_PATH}"
    
    # Stop Gitea to ensure consistent backup
    echo "Stopping Gitea service..."
    service gitea stop || true
    sleep 2
    
    # Backup Gitea data directories
    echo "Backing up Gitea configuration and data..."
    if [ -d /usr/local/etc/gitea ]; then
        tar -czf "${BACKUP_PATH}/gitea-config.tar.gz" -C /usr/local/etc gitea
        echo "  ✓ Configuration backed up"
    fi
    
    if [ -d /usr/local/share/gitea ]; then
        tar -czf "${BACKUP_PATH}/gitea-data.tar.gz" -C /usr/local/share gitea
        echo "  ✓ Data backed up"
    fi
    
    # Backup PostgreSQL database
    echo "Backing up PostgreSQL database..."
    if [ -f /root/dbname ] && [ -f /root/dbuser ]; then
        DB=$(cat /root/dbname)
        USER=$(cat /root/dbuser)
        
        su -m postgres -c "pg_dump -Fc ${DB}" > "${BACKUP_PATH}/gitea-db.dump"
        echo "  ✓ Database backed up"
        
        # Save database credentials
        cp /root/PLUGIN_INFO "${BACKUP_PATH}/PLUGIN_INFO" 2>/dev/null || true
    fi
    
    # Create backup manifest
    cat > "${BACKUP_PATH}/manifest.txt" <<EOF
Backup created: ${TIMESTAMP}
Gitea Version: $(pkg info gitea | grep Version | awk '{print $2}')
PostgreSQL Version: $(pkg info postgresql* | grep Version | head -1 | awk '{print $2}')
EOF
    
    # Restart Gitea
    echo "Restarting Gitea service..."
    service gitea start
    
    echo ""
    echo "=========================================="
    echo "Backup completed successfully!"
    echo "=========================================="
    echo "Backup location: ${BACKUP_PATH}"
    echo ""
}

restore_gitea() {
    if [ -z "$1" ]; then
        echo "Error: Please specify a backup name to restore"
        echo ""
        list_backups
        exit 1
    fi
    
    BACKUP_PATH="${BACKUP_DIR}/$1"
    
    if [ ! -d "${BACKUP_PATH}" ]; then
        echo "Error: Backup not found: ${BACKUP_PATH}"
        echo ""
        list_backups
        exit 1
    fi
    
    echo "=========================================="
    echo "Starting Gitea Restore"
    echo "=========================================="
    echo "WARNING: This will overwrite current Gitea data!"
    echo "Press Ctrl+C within 10 seconds to cancel..."
    sleep 10
    
    # Stop services
    echo "Stopping services..."
    service gitea stop || true
    service postgresql stop || true
    sleep 2
    
    # Restore Gitea configuration
    if [ -f "${BACKUP_PATH}/gitea-config.tar.gz" ]; then
        echo "Restoring Gitea configuration..."
        tar -xzf "${BACKUP_PATH}/gitea-config.tar.gz" -C /usr/local/etc
        echo "  ✓ Configuration restored"
    fi
    
    # Restore Gitea data
    if [ -f "${BACKUP_PATH}/gitea-data.tar.gz" ]; then
        echo "Restoring Gitea data..."
        tar -xzf "${BACKUP_PATH}/gitea-data.tar.gz" -C /usr/local/share
        echo "  ✓ Data restored"
    fi
    
    # Start PostgreSQL for database restore
    echo "Starting PostgreSQL..."
    service postgresql start
    sleep 3
    
    # Restore database
    # Note: This uses postgres superuser for restore operations.
    # This is acceptable in a TrueNAS jail environment where the restore
    # script is only accessible to the root user.
    if [ -f "${BACKUP_PATH}/gitea-db.dump" ]; then
        echo "Restoring PostgreSQL database..."
        if [ -f /root/dbname ] && [ -f /root/dbuser ]; then
            DB=$(cat /root/dbname)
            USER=$(cat /root/dbuser)
            
            # Drop and recreate database
            psql -U postgres -c "DROP DATABASE IF EXISTS ${DB};"
            psql -U postgres -c "CREATE DATABASE ${DB} WITH OWNER ${USER};"
            
            # Restore database
            su -m postgres -c "pg_restore -d ${DB} ${BACKUP_PATH}/gitea-db.dump"
            echo "  ✓ Database restored"
        fi
    fi
    
    # Fix permissions
    echo "Setting permissions..."
    chown -R git:git /usr/local/etc/gitea
    chown -R git:git /usr/local/share/gitea
    
    # Start Gitea
    echo "Starting Gitea service..."
    service gitea start
    
    echo ""
    echo "=========================================="
    echo "Restore completed successfully!"
    echo "=========================================="
}

list_backups() {
    echo "Available backups:"
    echo ""
    
    if [ ! -d "${BACKUP_DIR}" ]; then
        echo "  No backups found (backup directory doesn't exist)"
        return
    fi
    
    # Check if directory has any subdirectories
    has_backups=0
    for backup in "${BACKUP_DIR}"/*; do
        if [ -d "$backup" ]; then
            has_backups=1
            break
        fi
    done
    
    if [ $has_backups -eq 0 ]; then
        echo "  No backups found"
        return
    fi
    
    for backup in "${BACKUP_DIR}"/*; do
        if [ -d "$backup" ]; then
            backup_name=$(basename "$backup")
            echo "  📦 ${backup_name}"
            if [ -f "${backup}/manifest.txt" ]; then
                sed 's/^/     /' "${backup}/manifest.txt"
            fi
            echo ""
        fi
    done
}

# Main script
case "$1" in
    backup)
        backup_gitea
        ;;
    restore)
        restore_gitea "$2"
        ;;
    list)
        list_backups
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

exit 0
