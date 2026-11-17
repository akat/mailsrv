#!/usr/bin/env bash
# Συνεπές (cold) backup των volumes του Stalwart. Τρέχει στον host.
# Δουλεύει είτε το stack το έστησε το docker compose είτε το Portainer: τα volumes
# τα βρίσκει από το ίδιο το container.
# Σταματά τον server για λίγα δευτερόλεπτα: οι αποστολείς κάνουν retry, δεν χάνεται mail.
#
# Χρήση:   BACKUP_DIR=/opt/backups/stalwart ./scripts/backup.sh
# Cron:    15 3 * * * BACKUP_DIR=/opt/backups/stalwart /opt/mailsrv/scripts/backup.sh >> /opt/backups/stalwart/backup.log 2>&1
# Κράτα ΚΑΙ off-site αντίγραφο (restic/borg/rclone προς S3, άλλο server κ.λπ.).
set -euo pipefail

CONTAINER="${CONTAINER:-stalwart}"
DEST="${BACKUP_DIR:-$(cd "$(dirname "$0")/.." && pwd)/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="stalwart-$TS.tar.gz"
OWNER="${BACKUP_OWNER:-$(id -u):$(id -g)}"   # uid:gid του αρχείου backup

vol() {
  docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$1\"}}{{.Name}}{{end}}{{end}}" "$CONTAINER"
}
ETC_VOL="$(vol /etc/stalwart)"
DATA_VOL="$(vol /var/lib/stalwart)"
[[ -n "$ETC_VOL" && -n "$DATA_VOL" ]] || { echo "Δεν βρέθηκαν τα volumes του container '$CONTAINER'"; exit 1; }

mkdir -p "$DEST"
restart() { docker start "$CONTAINER" >/dev/null; }
trap restart EXIT

docker stop -t 60 "$CONTAINER" >/dev/null
docker run --rm \
  -v "$ETC_VOL:/src/etc:ro" \
  -v "$DATA_VOL:/src/data:ro" \
  -v "$DEST:/dest" \
  alpine:3.20 sh -c "umask 077 && tar -C /src -czf /dest/$OUT etc data && chown $OWNER /dest/$OUT"
restart
trap - EXIT

find "$DEST" -name 'stalwart-*.tar.gz' -mtime +"$KEEP_DAYS" -delete
echo "OK: $DEST/$OUT ($(du -h "$DEST/$OUT" | cut -f1))  [volumes: $ETC_VOL, $DATA_VOL]"

# Επαναφορά (στα ίδια volumes):
#   docker stop stalwart
#   docker run --rm -v <ETC_VOL>:/dst/etc -v <DATA_VOL>:/dst/data -v <BACKUP_DIR>:/b alpine:3.20 \
#     sh -c 'rm -rf /dst/etc/* /dst/data/* && tar -C /dst -xzf /b/stalwart-XXXX.tar.gz'
#   docker start stalwart     (στο Portainer: Containers -> stalwart -> Start)
