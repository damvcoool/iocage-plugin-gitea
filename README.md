# iocage-plugin-gitea

Unofficial [FreeCORE](https://github.com/freecore-project/) (TrueNAS CORE replacement) plugin to install [Gitea](https://gitea.com/).

---

## Installation

Run the following commands on your FreeCORE host:

```shell
BRANCH=master
JSON=/tmp/gitea.json

fetch -o "$JSON" "https://raw.githubusercontent.com/damvcoool/iocage-plugin-index/${BRANCH}/gitea.json"
iocage fetch -P "$JSON" --branch "$BRANCH" -n Gitea
```

---

## Post-Installation

After installation completes:

1. Navigate to `http://<jail-ip>:3000/install` in your web browser
2. Complete the web-based installation wizard
3. Use the database credentials displayed in the post-install output (also saved in `/root/PLUGIN_INFO`)

### Credentials Location

All credentials are stored securely in the jail's `/root` directory:

- `/root/PLUGIN_INFO` — Complete setup information including database credentials

---

## Configuration

### Service Management

```sh
# Start/Stop/Restart Gitea
service gitea start
service gitea stop
service gitea restart
service gitea status

# PostgreSQL
service postgresql start
service postgresql stop
service postgresql restart
```

### Configuration Files

- Gitea configuration: `/usr/local/etc/gitea/conf/app.ini`
- Environment variables can be customized in the configuration file

---

## Troubleshooting

### Common Issues

**Gitea won't start:**

- Check if PostgreSQL is running: `service postgresql status`
- Check log file for errors

**SSH for git over SSH:**

- SSH is enabled by default in this plugin
- Ensure port 22 is accessible if using git over SSH

---

## Version Information

- **Git**: Latest stable version
- **PostgreSQL**: Auto-dected version
- **FreeBSD**: Compatible with FreeCORE (FreeBSD-based)

---

## Features

- Automated PostgreSQL database setup with dynamic version detection
- Improved error handling and logging for easier troubleshooting
- Service health checks with proper wait mechanisms
- Enhanced IP address detection for various network configurations
- Better security practices (proper file permissions)
- Comprehensive post-install information display
- Support for both static and DHCP network configurations

---

## Contributing

This is a community project. Issues and pull requests are welcome!

## License

This plugin configuration is provided as-is. Gitea itself is licensed under MIT License.

## Disclaimer

This is an unofficial plugin not affiliated with or supported by Gitea or iXsystems. Use at your own risk. 
