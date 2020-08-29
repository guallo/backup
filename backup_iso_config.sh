#!/usr/bin/bash

source "$BACKUP_HOME/live/backup/backup_config.sh"

# 'ssh_known_hosts' file to use in the live system.
SSH_KNOWN_HOSTS_FILE_PATH=""

# Path to file with the credentials (if needed) to
# access the URL of the directory where to place the backup.
#
# An empty path ('') means no credentials.
DEST_CREDENTIALS_FILE_PATH=""

# Path to a program file to be executed after the backup process.
#
# That program file will be given execution permission before 
# been called as ./post_hook_executable with the user root from 
# a working directory created by the command 'mktemp -d' in the
# live system.
#
# The following environment variables are available:
#   - BACKUP_EXIT_CODE: the exit status code of the backup process.
#   - BACKUP_STDERR: the captured stderr stream of the backup process.
#
# An empty path ('') means no post hook.
POST_HOOK_EXECUTABLE_PATH=""

# URL to the original live ISO from which to build the backup ISO.
ORIGINAL_ISO_URL="sftp://user@host:22/path/to/original.iso"

# Path where to install the built backup live ISO.
BACKUP_ISO_PATH="/backup.iso"

BACKUP_ISO_MODE="600"

GRUB_TIMEOUT="60"
GRUB_TIMEOUT_STYLE="menu"
GRUB_MENU_ENTRY_CONFIG_FILE_PATH="/etc/grub.d/40_custom"
GRUB_DEFAULT_CONFIG_FILE_PATH="/etc/default/grub"
