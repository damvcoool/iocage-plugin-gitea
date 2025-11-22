## HOW-TO Install this fork

```shell
BRANCH=master
JSON=/tmp/gitea.json

fetch -o "$JSON" "https://raw.githubusercontent.com/damvcoool/iocage-plugin-index/${BRANCH}/gitea.json"
iocage fetch -P "$JSON" --branch "$BRANCH" -n Gitea
```

# iocage-plugin-gitea

A comprehensive iocage plugin for Gitea with enhanced TrueNAS Core 13 compatibility.

Gitea is a painless self-hosted Git service that is lightweight, easy to use, and provides a clean interface for managing repositories, users, and organizations.

## Features

- ✅ Automated PostgreSQL database setup with dynamic version detection
- ✅ Improved error handling and logging for easier troubleshooting
- ✅ Service health checks with proper wait mechanisms
- ✅ Enhanced IP address detection for various network configurations
- ✅ Better security practices (proper file permissions)
- ✅ Comprehensive post-install information display
- ✅ **NEW:** Backup and restore functionality
- ✅ **NEW:** Health check diagnostics
- ✅ **NEW:** Pre-upgrade automatic backups
- ✅ **NEW:** Helper scripts for maintenance

## Quick Start

### Installation

1. Install the plugin through TrueNAS:
   - Navigate to **Plugins** in the TrueNAS web interface
   - Find "Gitea" in the plugin list
   - Click **Install**

2. After installation, navigate to `http://<jail-ip>:3000/install`

3. Complete the installation wizard using the database credentials provided

### First-Time Setup

When you access Gitea for the first time, you'll need to complete the installation wizard:

1. **Database Settings** (pre-filled from installation):
   - Database Type: PostgreSQL
   - Host: 127.0.0.1:5432
   - Username: gitea
   - Password: (provided in post-install output)
   - Database Name: gitea

2. **General Settings**:
   - Site Title: Your choice
   - Repository Root Path: `/usr/local/share/gitea/gitea-repositories`
   - Git LFS Root Path: `/usr/local/share/gitea/data/lfs`
   - Run As Username: git

3. **Server and Third-Party Service Settings**:
   - SSH Server Domain: Your jail IP or hostname
   - SSH Port: 22
   - HTTP Port: 3000
   - Application URL: `http://your-jail-ip:3000/`

4. **Optional Settings**:
   - Email settings (SMTP)
   - Administrator account

5. Click **Install Gitea** to complete setup

## Database Setup

A PostgreSQL database is automatically configured during installation:
- **Database name:** `gitea`
- **Database user:** `gitea`
- **Database password:** A random password is generated and saved to `/root/PLUGIN_INFO`

The PostgreSQL database includes:
- pg_trgm extension for better search performance
- Proper authentication configuration
- Remote access capability (for administration)

You can use a different database type if you prefer, but you'll need to set it up manually.

## Post-Installation

After installation completes:
1. Navigate to `http://<jail-ip>:3000/install` in your web browser
2. Complete the web-based installation wizard
3. Use the database credentials displayed in the post-install output (also saved in `/root/PLUGIN_INFO`)

## Maintenance & Management

### Health Checks

Run comprehensive health checks to verify your Gitea installation:

```bash
gitea-health-check.sh
```

This checks:
- Service status (Gitea, PostgreSQL, SSH)
- Network connectivity and ports
- Database connection
- Disk space usage
- File permissions
- Configuration validity

### Backup and Restore

#### Creating a Backup

Create a full backup of Gitea data and database:

```bash
gitea-backup.sh backup
```

Backups are stored in `/root/gitea-backups/` and include:
- Gitea configuration files
- Repository data
- PostgreSQL database dump
- Plugin information

#### Listing Backups

View all available backups:

```bash
gitea-backup.sh list
```

#### Restoring from Backup

Restore from a specific backup:

```bash
gitea-backup.sh restore gitea-backup-YYYYMMDD-HHMMSS
```

**⚠️ Warning:** Restore will overwrite current data. You have 10 seconds to cancel.

### Viewing Database Credentials

If you need to retrieve the database credentials after installation:

```bash
cat /root/PLUGIN_INFO
```

### Upgrading

When upgrading the plugin:
- An automatic backup is created before the upgrade
- Services are restarted automatically
- Configuration and data are preserved

## Configuration

### SSH Access

SSH is enabled by default for Git operations over SSH. Users can clone repositories using:

```bash
git clone ssh://git@<jail-ip>:22/username/repository.git
```

### Accessing the Web Interface

- **Default URL:** `http://<jail-ip>:3000`
- **Installation Wizard:** `http://<jail-ip>:3000/install` (first time only)

### Firewall Configuration

If you're accessing Gitea from outside your local network, ensure these ports are accessible:
- **Port 3000:** HTTP web interface
- **Port 22:** SSH for Git operations

### Data Locations

- **Configuration:** `/usr/local/etc/gitea/conf/app.ini`
- **Data Directory:** `/usr/local/share/gitea/`
- **Repositories:** `/usr/local/share/gitea/gitea-repositories/`
- **Database Info:** `/root/PLUGIN_INFO`
- **Backups:** `/root/gitea-backups/`

## Troubleshooting

### Gitea won't start

1. Check service status:
   ```bash
   service gitea status
   ```

2. Run health check:
   ```bash
   gitea-health-check.sh
   ```

3. Check logs:
   ```bash
   tail -f /var/log/gitea.log
   ```

4. Verify permissions:
   ```bash
   chown -R git:git /usr/local/etc/gitea
   chown -R git:git /usr/local/share/gitea
   ```

### Database connection issues

1. Verify PostgreSQL is running:
   ```bash
   service postgresql status
   ```

2. Test database connection:
   ```bash
   psql -U gitea -d gitea -c "SELECT 1"
   ```

3. Check database credentials:
   ```bash
   cat /root/PLUGIN_INFO
   ```

### Can't access web interface

1. Verify Gitea is listening on port 3000:
   ```bash
   sockstat -l | grep 3000
   ```

2. Check jail IP address:
   ```bash
   ifconfig | grep inet
   ```

3. Verify firewall rules allow access to port 3000

### Installation wizard doesn't appear

If the installation wizard doesn't appear after navigating to `http://<jail-ip>:3000/install`:

1. Ensure the config file doesn't exist:
   ```bash
   rm -f /usr/local/etc/gitea/conf/app.ini
   ```

2. Restart Gitea:
   ```bash
   service gitea restart
   ```

### After upgrade, Gitea shows errors

1. Check the pre-upgrade backup:
   ```bash
   gitea-backup.sh list
   ```

2. If needed, restore from backup:
   ```bash
   gitea-backup.sh restore <backup-name>
   ```

3. Check service logs for specific errors:
   ```bash
   tail -f /var/log/gitea.log
   ```

### Low disk space

1. Check disk usage:
   ```bash
   df -h
   ```

2. Clean up old backups:
   ```bash
   rm -rf /root/gitea-backups/old-backup-name
   ```

3. Review repository size:
   ```bash
   du -sh /usr/local/share/gitea/gitea-repositories/*
   ```

## TrueNAS Core 13 Compatibility

This plugin has been optimized for TrueNAS Core 13 with:
- Dynamic PostgreSQL version detection (no hard-coded paths)
- Proper PostgreSQL authentication syntax
- Robust service startup validation
- Enhanced error handling for jail environments
- Support for both static and DHCP network configurations

## Security Considerations

- Database password is randomly generated and stored securely
- Proper file permissions are enforced for configuration and data
- PostgreSQL is configured to require password authentication
- SSH is enabled for Git operations but limited to git user
- Regular backups are recommended for data safety

## Performance Tips

1. **For larger repositories**, consider:
   - Increasing jail memory allocation
   - Using SSD storage for repository data
   - Enabling Git LFS for large files

2. **Database optimization:**
   - The pg_trgm extension is enabled for faster searches
   - Regular VACUUM operations keep the database healthy
   - Monitor database size and plan for growth

3. **Network performance:**
   - Use a dedicated VLAN for Git operations if handling sensitive data
   - Consider setting up a reverse proxy for HTTPS

## Advanced Configuration

### Using a Custom Domain

1. Update the application URL in `/usr/local/etc/gitea/conf/app.ini`:
   ```ini
   [server]
   DOMAIN = git.yourdomain.com
   ROOT_URL = https://git.yourdomain.com/
   ```

2. Configure your reverse proxy (outside the jail)

3. Restart Gitea:
   ```bash
   service gitea restart
   ```

### Email Configuration

Edit `/usr/local/etc/gitea/conf/app.ini` to add email settings:

```ini
[mailer]
ENABLED = true
SMTP_ADDR = smtp.example.com
SMTP_PORT = 587
FROM = gitea@yourdomain.com
USER = your-email@example.com
PASSWD = your-password
```

### Enabling Actions (CI/CD)

Gitea supports GitHub Actions-compatible CI/CD:

```ini
[actions]
ENABLED = true
```

Restart Gitea after making configuration changes.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Support

- **Issues:** Report bugs or request features via GitHub Issues
- **Documentation:** Gitea official documentation at https://docs.gitea.io/
- **Community:** Gitea community forums and Discord

## License

This plugin is released under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Gitea team for the excellent Git service
- TrueNAS/iocage community for the plugin framework
- Contributors who have helped improve this plugin
