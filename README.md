## HOW-TO Install this fork

```shell
BRANCH=master
JSON=/tmp/gitea.json

fetch -o "$JSON" "https://raw.githubusercontent.com/damvcoool/iocage-plugin-index/${BRANCH}/gitea.json"
iocage fetch -P "$JSON" --branch "$BRANCH" -n Gitea
```

# iocage-plugin-gitea

iocage plugin for Gitea with enhanced TrueNAS Core 13 compatibility.

## Features

- Automated PostgreSQL database setup with dynamic version detection
- Improved error handling and logging for easier troubleshooting
- Service health checks with proper wait mechanisms
- Enhanced IP address detection for various network configurations
- Better security practices (proper file permissions)
- Comprehensive post-install information display

## Database Setup

A PostgreSQL database is automatically configured during installation:
- Database name: `gitea`
- Database user: `gitea`
- A random password is generated and saved to `/root/PLUGIN_INFO`

You can use a different database type if you prefer, but you'll need to set it up manually.

## Post-Installation

After installation completes:
1. Navigate to `http://<jail-ip>:3000/install` in your web browser
2. Complete the web-based installation wizard
3. Use the database credentials displayed in the post-install output (also saved in `/root/PLUGIN_INFO`)

## TrueNAS Core 13 Compatibility

This plugin has been optimized for TrueNAS Core 13 with:
- Dynamic PostgreSQL version detection (no hard-coded paths)
- Proper PostgreSQL authentication syntax
- Robust service startup validation
- Enhanced error handling for jail environments
- Support for both static and DHCP network configurations 
