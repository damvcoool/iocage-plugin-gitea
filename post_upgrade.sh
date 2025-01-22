# Check existing config before starting
sysrc gitea_configcheck_enable=NO 2>/dev/null

# Set Permissions for config
chown -R git:git /usr/local/etc/gitea/conf
chown -R git:git /usr/local/share/gitea
chmod 777 /tmp
# Start Database
service postgresql start 2>/dev/null
sleep 5

# Start Gitea
service gitea start 2>/dev/null
sleep 5
