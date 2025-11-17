#!/bin/sh

# Function to wait for service to be running
wait_for_service() {
    local service_name=$1
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if service $service_name status >/dev/null 2>&1; then
            echo "$service_name is running"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    echo "Warning: $service_name did not start within expected time"
    return 1
}

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
