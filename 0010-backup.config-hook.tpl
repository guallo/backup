#!/usr/bin/bash

LIVE_HOME="$(eval echo "~$LIVE_USERNAME")"
LIVE_MEDIUM="$(mount | grep -Po '(?<= on ).+(?= type iso9660)' | head -n 1)"
LIVE_BACKUP_HOME="$LIVE_MEDIUM/live/backup"

cat << EOF >> "$LIVE_HOME/.profile"
if (flock -x 200 && ! test -f ~/backup.lock.lock && touch ~/backup.lock.lock) 200>~/backup.lock; then
    clear
    sudo bash "$LIVE_BACKUP_HOME/backup.sh" --dest-dir-url "{{dest_dir_url}}" --dest-credentials-file-path "{{dest_credentials_file_path}}" --blocks-num "{{blocks_num}}" --post-hook-executable-path "{{post_hook_executable_path}}"
fi
EOF
