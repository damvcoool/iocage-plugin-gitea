#!/bin/sh

# Exit on error
set -e

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

# Enable service
echo "Configuring Gitea service..."
sysrc gitea_enable=YES
sysrc gitea_configcheck_enable=NO

# Enable SSH for git over ssh
echo "Configuring SSH service..."
sysrc sshd_enable=YES
service sshd start || echo "Warning: SSH service may already be running"
wait_for_service sshd

# Start/stop service to generate configs
echo "Generating initial Gitea configuration..."
service gitea start
wait_for_service gitea
service gitea stop
sleep 3

# Remove default config to allow use of the web installer, set permissions
echo "Setting up Gitea directories..."
rm -f /usr/local/etc/gitea/conf/app.ini
chown -R git:git /usr/local/etc/gitea/conf
chown -R git:git /usr/local/share/gitea

# Start service
echo "Starting Gitea service..."
service gitea start
wait_for_service gitea
# Installer only comes up if there is no config so we nuke it once more to be sure
mv /usr/local/etc/gitea/conf/app.ini /usr/local/etc/gitea/conf/app.ini.old 2>/dev/null || true


# Setup Postgres
echo "Setting up PostgreSQL database..."
sysrc postgresql_enable="YES"

chmod 1777 /tmp

# Initialize PostgreSQL database
# The initdb command is idempotent and will skip if already initialized
echo "Initializing PostgreSQL database..."
service postgresql initdb
echo "PostgreSQL initialization complete"

echo "Starting PostgreSQL service..."
service postgresql start
wait_for_service postgresql

USER="gitea"
DB="gitea"

# Save the config values
echo "Creating database credentials..."
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser
export LC_ALL=C
tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1 > /root/dbpassword
PASS=$(cat /root/dbpassword)

echo "Creating PostgreSQL user and database..."
# Create user
if ! psql -d template1 -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${USER}'" | grep -q 1; then
    psql -d template1 -U postgres -c "CREATE USER ${USER} CREATEDB;"
    echo "User ${USER} created"
else
    echo "User ${USER} already exists"
fi

# Create production database & grant all privileges on database
if ! psql -d template1 -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB}'" | grep -q 1; then
    psql -d template1 -U postgres -c "CREATE DATABASE ${DB} WITH OWNER ${USER} TEMPLATE template0 ENCODING UTF8 LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';"
    echo "Database ${DB} created"
else
    echo "Database ${DB} already exists"
fi

# Set a password on the postgres account using correct PostgreSQL syntax
psql -d template1 -U postgres -c "ALTER USER ${USER} WITH PASSWORD '${PASS}';"
echo "Password set for user ${USER}"

# Connect as superuser and enable pg_trgm extension
psql -U postgres -d ${DB} -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
echo "PostgreSQL pg_trgm extension enabled"

# Configure PostgreSQL to allow remote connections
echo "Configuring PostgreSQL access..."
# Detect PostgreSQL data directory dynamically
PG_DATA_DIR=$(psql -U postgres -t -c "SHOW data_directory;" 2>/dev/null | xargs)

if [ -n "$PG_DATA_DIR" ] && [ -d "$PG_DATA_DIR" ]; then
    echo "PostgreSQL data directory: $PG_DATA_DIR"
    
    # Check if configuration already exists
    if ! grep -q "listen_addresses = '\*'" "$PG_DATA_DIR/postgresql.conf" 2>/dev/null; then
        echo "listen_addresses = '*'" >> "$PG_DATA_DIR/postgresql.conf"
        echo "Added listen_addresses to postgresql.conf"
    fi
    
    if ! grep -q "host  all  all 0.0.0.0/0 md5" "$PG_DATA_DIR/pg_hba.conf" 2>/dev/null; then
        echo "host  all  all 0.0.0.0/0 md5" >> "$PG_DATA_DIR/pg_hba.conf"
        echo "Added host entry to pg_hba.conf"
    fi
    
    # Restart postgresql after config change
    echo "Restarting PostgreSQL to apply configuration..."
    service postgresql restart
    wait_for_service postgresql
else
    echo "Warning: Could not detect PostgreSQL data directory, skipping remote access configuration"
fi

# Save database information
echo "Saving database configuration..."
cat > /root/PLUGIN_INFO <<EOF
Host: localhost or 127.0.0.1
Database Type: PostgreSQL
Database Name: $DB
Database User: $USER
Database Password: $PASS
EOF

# Install helper scripts to system path
echo "Installing helper scripts..."
if [ -f /root/gitea-backup.sh ]; then
    cp /root/gitea-backup.sh /usr/local/bin/gitea-backup.sh
    chmod +x /usr/local/bin/gitea-backup.sh
    echo "  ✓ Backup script installed to /usr/local/bin/gitea-backup.sh"
fi

if [ -f /root/health-check.sh ]; then
    cp /root/health-check.sh /usr/local/bin/gitea-health-check.sh
    chmod +x /usr/local/bin/gitea-health-check.sh
    echo "  ✓ Health check script installed to /usr/local/bin/gitea-health-check.sh"
fi

if [ -f /root/pluginget ]; then
    cp /root/pluginget /usr/local/bin/pluginget
    chmod +x /usr/local/bin/pluginget
fi

if [ -f /root/pluginset ]; then
    cp /root/pluginset /usr/local/bin/pluginset
    chmod +x /usr/local/bin/pluginset
fi

echo "Detecting jail IP address..."
# Get the jail's primary IP address
# Try multiple methods to be robust across different network configurations
IP=""

# Method 1: Check for iocage environment variable (most reliable for iocage jails)
if [ -n "$IOCAGE_PLUGIN_IP" ]; then
    IP="$IOCAGE_PLUGIN_IP"
    echo "Using IOCAGE_PLUGIN_IP: $IP"
# Method 2: Get from ifconfig (works for static IPs)
elif IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1); then
    echo "Detected IP from ifconfig: $IP"
# Method 3: Fallback to hostname resolution
elif IP=$(hostname -I 2>/dev/null | awk '{print $1}'); then
    echo "Detected IP from hostname: $IP"
else
    # Final fallback
    IP="<jail-ip-address>"
    echo "Could not auto-detect IP, using placeholder"
fi

# Show user database details 
echo "-------------------------------------------------------"
echo "GITEA INSTALLATION COMPLETE"
echo "-------------------------------------------------------"
echo ""
echo "DATABASE INFORMATION:"
echo "  Host: localhost or 127.0.0.1" 
echo "  Database Type: PostgreSQL" 
echo "  Database Name: $DB" 
echo "  Database User: $USER" 
echo "  Database Password: $PASS" 
echo ""
echo "NEXT STEPS:"
echo "  1. Open your web browser and navigate to:"
echo "     http://${IP}:3000/install"
echo "  2. Complete the web-based installation wizard"
echo "  3. Use the database credentials shown above"
echo ""
echo "HELPFUL COMMANDS:"
echo "  - Health Check: gitea-health-check.sh"
echo "  - Backup: gitea-backup.sh backup"
echo "  - Restore: gitea-backup.sh restore <backup-name>"
echo "  - List Backups: gitea-backup.sh list"
echo ""
echo "NOTE: To review this information again, click 'Post Install Notes'"
echo "      or check the file /root/PLUGIN_INFO"
echo "-------------------------------------------------------"
