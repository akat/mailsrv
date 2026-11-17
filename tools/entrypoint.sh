#!/usr/bin/env bash
set -euo pipefail
S=/opt/mailsrv/scripts

usage() {
  cat <<'EOF'
mailsrv-tools <command> [args]

  check-dns <domain> [mail-host]   Έλεγχος MX/SPF/DKIM/DMARC/MTA-STS/TLS-RPT/SRV
                                   (DKIM_SELECTORS="s1 s2" για έλεγχο DKIM)
  preflight <mail-host>            Έλεγχοι server: PTR, θύρα 25, blacklists, θύρες
                                   (θέλει --network host, MODE=traefik πίσω από Traefik)
  backup                           Cold backup των volumes του container "stalwart"
                                   (θέλει docker.sock και BACKUP_DIR = ίδιο path host/container)

Παραδείγματα:
  docker run --rm IMAGE check-dns example.com
  docker run --rm --network host -e MODE=traefik IMAGE preflight mail.example.com
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    -v /opt/backups/stalwart:/opt/backups/stalwart -e BACKUP_DIR=/opt/backups/stalwart IMAGE backup
EOF
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  check-dns) exec "$S/check-dns.sh" "$@" ;;
  preflight) exec "$S/preflight.sh" "$@" ;;
  backup)
    # Το backup.sh κάνει `docker run -v $BACKUP_DIR:...`: το path λύνεται στον HOST,
    # άρα πρέπει να είναι mount στο ίδιο path μέσα σε αυτό το container.
    [[ -S /var/run/docker.sock ]] || { echo "Λείπει: -v /var/run/docker.sock:/var/run/docker.sock"; exit 2; }
    [[ -n "${BACKUP_DIR:-}" ]] || { echo "Λείπει: -e BACKUP_DIR=/path (και -v /path:/path)"; exit 2; }
    mountpoint -q "$BACKUP_DIR" || { echo "Το $BACKUP_DIR δεν είναι mount: -v $BACKUP_DIR:$BACKUP_DIR"; exit 2; }
    exec "$S/backup.sh" "$@" ;;
  help|-h|--help) usage ;;
  *) echo "Άγνωστη εντολή: $cmd"; usage; exit 2 ;;
esac
