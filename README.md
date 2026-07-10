# Net253
misc Net253 things.

.rsc export do not contain secrets
user (name,pass,keys), wg private keys, all need to be added 
manually or via templating for proper restoration

## Restoration procedure

1. Upload the file to the device
2. apply the config:

```
/system reset-configuration no-defaults=yes skip-backup=yes run-after-reset=PATH_TO_FILE
```