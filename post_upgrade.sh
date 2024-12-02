# Set Permissions for config
chown -R git:git /usr/local/etc/gitea/conf
chown -R git:git /usr/local/share/gitea

# Start Database
service postgresql start 2>/dev/null
sleep 5

# Start Gitea
service gitea start 2>/dev/null
sleep 5
