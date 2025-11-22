#!/bin/sh
# Gitea Health Check Script
# This script performs comprehensive health checks on the Gitea installation

set -e

# ANSI color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

print_status() {
    status=$1
    message=$2
    
    if [ "$status" = "OK" ]; then
        printf "${GREEN}✓${NC} %s\n" "$message"
    elif [ "$status" = "WARN" ]; then
        printf "${YELLOW}⚠${NC} %s\n" "$message"
    else
        printf "${RED}✗${NC} %s\n" "$message"
    fi
}

check_service() {
    service_name=$1
    if service "$service_name" status >/dev/null 2>&1; then
        print_status "OK" "$service_name is running"
        return 0
    else
        print_status "ERROR" "$service_name is NOT running"
        return 1
    fi
}

check_port() {
    port=$1
    service_name=$2
    
    if sockstat -l | grep -q ":${port}"; then
        print_status "OK" "$service_name is listening on port $port"
        return 0
    else
        print_status "ERROR" "$service_name is NOT listening on port $port"
        return 1
    fi
}

check_database_connection() {
    if [ ! -f /root/dbname ] || [ ! -f /root/dbuser ]; then
        print_status "WARN" "Database credentials not found"
        return 1
    fi
    
    DB=$(cat /root/dbname)
    USER=$(cat /root/dbuser)
    
    if psql -U "$USER" -d "$DB" -c "SELECT 1" >/dev/null 2>&1; then
        print_status "OK" "PostgreSQL database connection successful"
        return 0
    else
        print_status "ERROR" "Cannot connect to PostgreSQL database"
        return 1
    fi
}

check_disk_space() {
    usage=$(df -h /usr/local/share/gitea | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$usage" -lt 80 ]; then
        print_status "OK" "Disk space: ${usage}% used"
        return 0
    elif [ "$usage" -lt 90 ]; then
        print_status "WARN" "Disk space: ${usage}% used (Warning: getting high)"
        return 0
    else
        print_status "ERROR" "Disk space: ${usage}% used (Critical: very high)"
        return 1
    fi
}

check_file_permissions() {
    errors=0
    
    if [ -d /usr/local/etc/gitea ]; then
        owner=$(stat -f "%Su:%Sg" /usr/local/etc/gitea)
        if [ "$owner" = "git:git" ]; then
            print_status "OK" "Configuration directory permissions correct"
        else
            print_status "ERROR" "Configuration directory owned by $owner (should be git:git)"
            errors=$((errors + 1))
        fi
    fi
    
    if [ -d /usr/local/share/gitea ]; then
        owner=$(stat -f "%Su:%Sg" /usr/local/share/gitea)
        if [ "$owner" = "git:git" ]; then
            print_status "OK" "Data directory permissions correct"
        else
            print_status "ERROR" "Data directory owned by $owner (should be git:git)"
            errors=$((errors + 1))
        fi
    fi
    
    return $errors
}

check_gitea_config() {
    if [ -f /usr/local/etc/gitea/conf/app.ini ]; then
        print_status "OK" "Gitea configuration file exists"
        
        # Check if configuration is valid
        if grep -q "APP_NAME" /usr/local/etc/gitea/conf/app.ini 2>/dev/null; then
            print_status "OK" "Gitea configuration appears valid"
        else
            print_status "WARN" "Gitea configuration may be incomplete"
        fi
    else
        print_status "WARN" "Gitea configuration file not found (first-time setup needed)"
    fi
}

print_system_info() {
    print_header "System Information"
    
    echo "Hostname: $(hostname)"
    echo "OS: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"
    
    if command -v pkg >/dev/null 2>&1; then
        gitea_version=$(pkg info gitea 2>/dev/null | grep Version | awk '{print $2}')
        if [ -n "$gitea_version" ]; then
            echo "Gitea Version: $gitea_version"
        fi
        
        pg_version=$(pkg info postgresql* 2>/dev/null | grep Version | head -1 | awk '{print $2}')
        if [ -n "$pg_version" ]; then
            echo "PostgreSQL Version: $pg_version"
        fi
    fi
}

print_network_info() {
    print_header "Network Information"
    
    # Get IP addresses
    echo "IP Addresses:"
    ifconfig | grep -E "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}'
    
    # Check listening ports
    echo ""
    echo "Listening Ports:"
    sockstat -l | grep -E "(gitea|postgres)" | awk '{print "  " $0}'
}

print_database_info() {
    print_header "Database Information"
    
    if [ -f /root/PLUGIN_INFO ]; then
        cat /root/PLUGIN_INFO
    else
        echo "Database information not found in /root/PLUGIN_INFO"
    fi
}

# Main health check
main() {
    overall_status=0
    
    print_header "Gitea Health Check"
    echo "Running comprehensive health checks..."
    
    print_header "Service Status"
    check_service "gitea" || overall_status=1
    check_service "postgresql" || overall_status=1
    check_service "sshd" || overall_status=1
    
    print_header "Network Connectivity"
    check_port "3000" "Gitea web interface" || overall_status=1
    check_port "22" "SSH" || overall_status=1
    
    print_header "Database Health"
    check_database_connection || overall_status=1
    
    print_header "Disk Space"
    check_disk_space || overall_status=1
    
    print_header "File Permissions"
    check_file_permissions || overall_status=1
    
    print_header "Configuration"
    check_gitea_config
    
    # Print additional information
    print_system_info
    print_network_info
    print_database_info
    
    # Summary
    print_header "Health Check Summary"
    if [ $overall_status -eq 0 ]; then
        print_status "OK" "All checks passed! Gitea is healthy."
    else
        print_status "ERROR" "Some checks failed. Please review the output above."
    fi
    
    echo ""
    
    return $overall_status
}

main
exit $?
