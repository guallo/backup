#!/usr/bin/bash

# URL to the directory where to place the backup.
DEST_DIR_URL="sftp://user@host:22/backup/dest/dir/"

# Path to file with the credentials (if needed) to
# access the URL of the directory where to place the backup.
#
# The path can start with the {{live_medium}} placeholder
# to refer to a file relative to the iso's mount point.
#
# An empty path ('') means no credentials.
DEST_CREDENTIALS_FILE_PATH=""

# In seconds.
RETRY_TIMEOUT="90"

# Number of blocks to backup for each disk.
#
# An empty value ('') means all blocks (i.e. the whole disk).
BLOCKS_NUM=""

# Path to a program file to be executed after the backup process.
#
# That program file will be given execution permission before 
# been called as ./post_hook_executable with the user root from 
# a working directory created by the command 'mktemp -d'.
#
# The following environment variables are available:
#   - BACKUP_EXIT_CODE: the exit status code of the backup process.
#   - BACKUP_STDERR: the captured stderr stream of the backup process.
#
# The path can start with the {{live_medium}} placeholder
# to refer to a program file relative to the iso's mount point.
#
# An empty path ('') means no post hook.
POST_HOOK_EXECUTABLE_PATH=""
