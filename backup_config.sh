#!/usr/bin/bash

# Path to the backup live ISO.
BACKUP_ISO_PATH=""

# Path to a program file to be executed before rebooting to start
# the backup process.
#
# If the pre-hook exits with non-zero status code the backup process
# will be cancelled. If the process previous to backup (and previous
# to the pre-hook) exits with non-zero status code (see environment
# variable PRE_BACKUP_EXIT_CODE below) the backup process will be
# cancelled too regarless of the exit code of the pre-hook.
#
# That program file will be given execution permission before
# been called as ./pre_hook_executable with the user root from
# a working directory created by the command 'mktemp -d' in the
# current system (not the live system).
#
# The following environment variables are available to the pre-hook:
#   - PRE_BACKUP_EXIT_CODE: the exit status code of the process
#       previous to backup.
#   - PRE_BACKUP_STDERR: the captured stderr stream of the process
#       previous to backup.
#
# An empty path ('') means no pre-hook.
PRE_HOOK_EXECUTABLE_PATH=""
