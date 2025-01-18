## HOW-TO Install this fork

```shell
BRANCH=master
JSON=/tmp/gitea.json

fetch -o "$JSON" "https://raw.githubusercontent.com/damvcoool/iocage-plugin-index/${BRANCH}/gitea.json"
iocage fetch -P "$JSON" --branch "$BRANCH" -n Gitea
```

# iocage-plugin-gitea

iocage plugin for Gitea. A Postgres database is already setup as part of the installation process but the user can chose a different database type and set that up manually if they wish. 
