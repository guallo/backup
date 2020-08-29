#!/usr/bin/bash

SMTP_SERVER_NAME='smtp.server.name'
SMTP_TLS_PORT='587'
SMTP_USERNAME='username@usernamedomain'
SMTP_PASSWORD='password'
SMTP_TIMEOUT_SEC='60'

FROM='sender@senderdomain'
TO='
recipient1@recipient1domain
recipient2@recipient2domain
'

PRE_HOOK_SUCCESSFUL_SUBJECT="The system will reboot to start the backup."
PRE_HOOK_SUCCESSFUL_CONTENT="
The system will reboot to start the backup.
"

PRE_HOOK_FAILED_SUBJECT="The backup was cancelled."
PRE_HOOK_FAILED_CONTENT="
The backup was cancelled because the previous process failed with exit code: $PRE_BACKUP_EXIT_CODE.
Below are the error messages:
$PRE_BACKUP_STDERR
"

POST_HOOK_SUCCESSFUL_SUBJECT="The backup was successful."
POST_HOOK_SUCCESSFUL_CONTENT="
The backup was successful.
"

POST_HOOK_FAILED_SUBJECT="The backup failed."
POST_HOOK_FAILED_CONTENT="
The backup failed with exit code: $BACKUP_EXIT_CODE.
Below are the error messages:
$BACKUP_STDERR
"

###########################
### DO NOT MODIFY BELOW ###
###########################

if [ -n "${PRE_BACKUP_EXIT_CODE+x}" ]; then
    EXIT_CODE=$PRE_BACKUP_EXIT_CODE
    
    SUCCESSFUL_SUBJECT="$PRE_HOOK_SUCCESSFUL_SUBJECT"
    SUCCESSFUL_CONTENT="$PRE_HOOK_SUCCESSFUL_CONTENT"
    
    FAILED_SUBJECT="$PRE_HOOK_FAILED_SUBJECT"
    FAILED_CONTENT="$PRE_HOOK_FAILED_CONTENT"
else
    EXIT_CODE=$BACKUP_EXIT_CODE
    
    SUCCESSFUL_SUBJECT="$POST_HOOK_SUCCESSFUL_SUBJECT"
    SUCCESSFUL_CONTENT="$POST_HOOK_SUCCESSFUL_CONTENT"
    
    FAILED_SUBJECT="$POST_HOOK_FAILED_SUBJECT"
    FAILED_CONTENT="$POST_HOOK_FAILED_CONTENT"
fi

apt-get update >/dev/null 2>&1
apt-get -y install python3 >/dev/null 2>&1

join_by_char() {
    local char="$1"; shift
    
    local IFS="$char"
    
    echo "$*"
}

python3 <(cat <<EOF
import ssl
import smtplib

from email.message import EmailMessage

msg = EmailMessage()
msg['From'] = '''$FROM'''
msg['To'] = '''$(join_by_char , $TO)'''

if $EXIT_CODE:
    subject = '''$FAILED_SUBJECT'''
    content = '''$FAILED_CONTENT'''
else:
    subject = '''$SUCCESSFUL_SUBJECT'''
    content = '''$SUCCESSFUL_CONTENT'''

msg['Subject'] = subject
msg.set_content(content)

with smtplib.SMTP('''$SMTP_SERVER_NAME''', $SMTP_TLS_PORT, timeout=$SMTP_TIMEOUT_SEC) as server:
    server.starttls(context=ssl.create_default_context())
    server.login('''$SMTP_USERNAME''', '''$SMTP_PASSWORD''')
    server.send_message(msg)
EOF
)
