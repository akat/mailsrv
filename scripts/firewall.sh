#!/usr/bin/env bash
# Βασικοί κανόνες ufw για τον mail server (τρέχει ως root).
# Λειτουργεί σωστά επειδή το compose χρησιμοποιεί network_mode: host.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Τρέξε το με sudo"; exit 1; }

SSH_PORT="${SSH_PORT:-22}"

ufw default deny incoming
ufw default allow outgoing
ufw limit "$SSH_PORT"/tcp comment 'SSH'
ufw allow 25/tcp   comment 'SMTP'
ufw allow 465/tcp  comment 'SMTPS submission'
ufw allow 587/tcp  comment 'Submission'
ufw allow 993/tcp  comment 'IMAPS'
ufw allow 4190/tcp comment 'ManageSieve'
ufw allow 443/tcp  comment 'HTTPS admin/JMAP/MTA-STS/ACME'
# 8080 (HTTP admin) μένει κλειστή: πρόσβαση μόνο με  ssh -L 8080:127.0.0.1:8080
ufw deny 8080/tcp  comment 'Stalwart HTTP admin - SSH tunnel only'
ufw --force enable
ufw status verbose
