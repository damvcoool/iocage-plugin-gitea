# iocage-plugin-gitea

Unofficial [FreeCORE](https://github.com/freecore-project/) (TrueNAS CORE replacement) plugin to install [Gitea](https://gitea.com/).

> **Status**: Personal plugin — not affiliated with or supported by Gitea or iXsystems.

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

After installation completes, you can access:

- **Web Interface**: `http://[jail-ip]:3000/install`
- **Default Login**: Complete the web-based setup wizard on first visit

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
- PostgreSQL settings are configured automatically during installation

---

## Features

- Automated PostgreSQL database setup with dynamic version detection
- Improved error handling and logging for easier troubleshooting
- Service health checks with proper wait mechanisms
- Enhanced IP address detection for various network configurations
- Better security practices with proper file permissions
- Comprehensive post-install information display
- Support for both static and DHCP network configurations

---

## Troubleshooting

### Common Issues

**Gitea won't start:**

- Check if PostgreSQL is running: `service postgresql status`
- Review the Gitea log output and jail console for errors

**SSH for git over SSH:**

- SSH is enabled by default in this plugin
- Ensure port 22 is accessible if using git over SSH

---

## Version Information

- **Git**: Latest stable version
- **PostgreSQL**: Auto-detected version
- **FreeBSD**: Compatible with FreeCORE (FreeBSD-based)

---

## Contributing

This is a community project. Issues and pull requests are welcome!

## License

This plugin configuration is provided as-is. Gitea itself is licensed under the MIT License.

## Disclaimer

This is an unofficial plugin not affiliated with or supported by Gitea or iXsystems. Use at your own risk.