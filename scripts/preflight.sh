#!/usr/bin/env bash
# Έλεγχοι στον server ΠΡΙΝ το πρώτο `docker compose up`.
# Χρήση: ./scripts/preflight.sh mail.example.com
#   Πίσω από Traefik/Portainer (οι 443/8080 ανήκουν στον Traefik):
#   MODE=traefik ./scripts/preflight.sh mail.example.com
set -uo pipefail

HOST="${1:-}"
if [[ -z "$HOST" && -f .env ]]; then
  HOST="$(grep -E '^STALWART_HOSTNAME=' .env | cut -d= -f2-)"
fi
[[ -n "$HOST" ]] || { echo "Χρήση: $0 mail.example.com"; exit 2; }

ok()   { printf '  \e[32m✔\e[0m %s\n' "$*"; }
bad()  { printf '  \e[31m✘\e[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*"; }
FAIL=0

echo "== Εργαλεία"
for c in docker dig curl nc; do
  command -v "$c" >/dev/null && ok "$c" || bad "λείπει το $c (apt install dnsutils curl netcat-openbsd)"
done
docker compose version >/dev/null 2>&1 && ok "docker compose" || bad "λείπει το docker compose plugin"

echo "== Δημόσια IP & DNS"
PUB4="$(curl -4 -fsS --max-time 5 https://api.ipify.org || true)"
PUB6="$(curl -6 -fsS --max-time 5 https://api6.ipify.org || true)"
[[ -n "$PUB4" ]] && ok "Δημόσια IPv4: $PUB4" || bad "Δεν βρέθηκε δημόσια IPv4"

A="$(dig +short A "$HOST" | tail -n1)"
[[ "$A" == "$PUB4" ]] && ok "A $HOST -> $A" || bad "A $HOST -> '${A:-κενό}' (αναμενόταν $PUB4)"

PTR="$(dig +short -x "$PUB4" | sed 's/\.$//')"
[[ "$PTR" == "$HOST" ]] && ok "PTR $PUB4 -> $PTR" \
  || bad "PTR $PUB4 -> '${PTR:-κενό}' (πρέπει $HOST - ρύθμισέ το στον πάροχο του VPS)"

if [[ "${MODE:-standalone}" == "traefik" ]]; then
  AAAA="$(dig +short AAAA "$HOST" | tail -n1)"
  [[ -z "$AAAA" ]] && ok "Χωρίς AAAA για $HOST (σωστό: το stack δέχεται/στέλνει μόνο IPv4)" \
    || bad "Το $HOST έχει AAAA ($AAAA): σβήσ' το. Το stack ακούει μόνο σε IPv4"
elif [[ -n "$PUB6" ]]; then
  warn "Ο server έχει IPv6 ($PUB6): τα εξερχόμενα θα φεύγουν και από IPv6."
  PTR6="$(dig +short -x "$PUB6" | sed 's/\.$//')"
  [[ "$PTR6" == "$HOST" ]] && ok "PTR $PUB6 -> $PTR6" \
    || bad "PTR IPv6 -> '${PTR6:-κενό}' (πρέπει $HOST, αλλιώς Gmail/Outlook απορρίπτουν)"
  AAAA="$(dig +short AAAA "$HOST" | tail -n1)"
  [[ "$AAAA" == "$PUB6" ]] && ok "AAAA $HOST -> $AAAA" || bad "AAAA $HOST -> '${AAAA:-κενό}' (αναμενόταν $PUB6)"
fi

echo "== Εξερχόμενη θύρα 25 (πολλοί πάροχοι την μπλοκάρουν)"
if timeout 8 nc -z -w5 gmail-smtp-in.l.google.com 25 2>/dev/null; then
  ok "Εξερχόμενο 25 ανοιχτό"
else
  bad "Εξερχόμενο 25 ΚΛΕΙΣΤΟ - ζήτα unblock από τον πάροχο (Hetzner/AWS/GCP/Azure το κλειδώνουν by default)"
fi

echo "== Ελεύθερες θύρες στον host"
PORTS="25 465 587 993 4190"
[[ "${MODE:-standalone}" == "traefik" ]] || PORTS="$PORTS 443 8080"
for p in $PORTS; do
  if ss -ltnH "sport = :$p" 2>/dev/null | grep -q .; then
    bad "Η θύρα $p χρησιμοποιείται ήδη: $(ss -ltnpH "sport = :$p" 2>/dev/null | awk '{print $NF}' | head -1)"
  else
    ok "θύρα $p ελεύθερη"
  fi
done

echo "== Blacklists (IPv4)"
REV="$(awk -F. '{print $4"."$3"."$2"."$1}' <<<"$PUB4")"
for bl in zen.spamhaus.org bl.spamcop.net b.barracudacentral.org psbl.surriel.com; do
  r="$(dig +short "$REV.$bl" A | head -1)"
  case "$r" in
    "") ok "όχι στο $bl" ;;
    127.255.255.*) warn "$bl: το query μπλοκαρίστηκε (public resolver) - έλεγξε στο https://check.spamhaus.org" ;;
    *) bad "ΣΤΗ ΛΙΣΤΑ $bl ($r) - ζήτα άλλη IP ή κάνε delisting" ;;
  esac
done

echo
[[ $FAIL -eq 0 ]] && echo "Όλα εντάξει." || { echo "Υπάρχουν προβλήματα - διόρθωσέ τα πριν βγεις σε παραγωγή."; exit 1; }
