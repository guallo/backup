# backup

## Install the backup iso

```bash
ssh-keyscan -H -p 22 <SFTP-SERVER> > custom_ssh_known_hosts

# save the password of the 'backup-store' user
nano backup-store-password

cp pre-post-hook-email.sh notify-by-email.sh

# configure the email parameters
nano notify-by-email.sh

sudo bash install_backup_iso.sh \
    --dest-dir-url sftp://backup-store@<SFTP-SERVER>:22/backup-store \
    --dest-credentials-file-path backup-store-password \
    --ssh-known-hosts-file-path custom_ssh_known_hosts \
    --post-hook-executable-path notify-by-email.sh \
    --original-iso-url sftp://public@<SFTP-SERVER>:22/public/debian-live-10.4.0-amd64-standard.iso \
    --backup-iso-path /backup.iso \
    --apt-get-assume-yes
```

## Trigger the backup process

```bash
sudo bash backup.sh \
    --backup-iso-path /backup.iso \
    --pre-hook-executable-path notify-by-email.sh \
    --apt-get-assume-yes
```
