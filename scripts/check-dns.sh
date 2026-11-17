#!/usr/bin/env bash
# Έλεγχος των DNS records που επηρεάζουν το deliverability ενός domain.
# Χρήση: ./scripts/check-dns.sh example.com [mail.example.com]
set -uo pipefail

DOMAIN="${1:-}"
[[ -n "$DOMAIN" ]] || { echo "Χρήση: $0 example.com [mail.example.com]"; exit 2; }
HOST="${2:-mail.$DOMAIN}"
R="@1.1.1.1"   # ρωτάμε public resolver για να δούμε ό,τι βλέπει ο υπόλοιπος κόσμος

ok()   { printf '  \e[32m✔\e[0m %s\n' "$*"; }
bad()  { printf '  \e[31m✘\e[0m %s\n' "$*"; FAIL=1; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*"; }
txt()  { dig +short TXT "$1" $R | tr -d '"' | sed 's/" "//g'; }
FAIL=0

echo "== $HOST"
A="$(dig +short A "$HOST" $R | tail -n1)"
[[ -n "$A" ]] && ok "A -> $A" || bad "Λείπει A record για $HOST"
if [[ -n "$A" ]]; then
  PTR="$(dig +short -x "$A" $R | sed 's/\.$//')"
  [[ "$PTR" == "$HOST" ]] && ok "PTR $A -> $PTR (FCrDNS)" || bad "PTR $A -> '${PTR:-κενό}' (πρέπει $HOST)"
fi
AAAA="$(dig +short AAAA "$HOST" $R | tail -n1)"
if [[ -n "$AAAA" ]]; then
  PTR6="$(dig +short -x "$AAAA" $R | sed 's/\.$//')"
  [[ "$PTR6" == "$HOST" ]] && ok "PTR $AAAA -> $PTR6" || bad "PTR IPv6 $AAAA -> '${PTR6:-κενό}' (πρέπει $HOST)"
fi
HSPF="$(txt "$HOST" | grep -i '^v=spf1')"
[[ -n "$HSPF" ]] && ok "SPF για HELO: $HSPF" || warn "Χωρίς SPF στο $HOST (προτείνεται: v=spf1 a -all)"

echo "== $DOMAIN"
MX="$(dig +short MX "$DOMAIN" $R)"
grep -qi " $HOST\.\?$" <<<"$MX" && ok "MX -> $(tr '\n' ' ' <<<"$MX")" || bad "MX δεν δείχνει στο $HOST: '${MX:-κενό}'"

SPF="$(txt "$DOMAIN" | grep -i '^v=spf1')"
n="$(grep -c . <<<"$SPF")"
if [[ "$n" -eq 1 ]]; then
  ok "SPF: $SPF"
  grep -qE '[-~]all$' <<<"$SPF" || warn "Το SPF δεν τελειώνει σε -all/~all"
elif [[ "$n" -gt 1 ]]; then bad "Πολλαπλά SPF records (permerror)"; else bad "Λείπει SPF"; fi

DMARC="$(txt "_dmarc.$DOMAIN" | grep -i '^v=DMARC1')"
if [[ -n "$DMARC" ]]; then
  ok "DMARC: $DMARC"
  grep -qi 'p=none' <<<"$DMARC" && warn "DMARC p=none: αφού δεις καθαρά reports, ανέβασε σε quarantine/reject"
  grep -qi 'rua=' <<<"$DMARC" || warn "DMARC χωρίς rua= (δεν θα παίρνεις aggregate reports)"
else bad "Λείπει DMARC (_dmarc.$DOMAIN) - απαραίτητο για Gmail/Yahoo/Outlook"; fi

for sel in ${DKIM_SELECTORS:-}; do
  D="$(txt "$sel._domainkey.$DOMAIN")"
  [[ -n "$D" ]] && ok "DKIM $sel: ${D:0:60}..." || bad "DKIM $sel._domainkey.$DOMAIN λείπει"
done
if [[ -z "${DKIM_SELECTORS:-}" ]]; then
  warn "Δώσε DKIM_SELECTORS=\"sel1 sel2\" για έλεγχο DKIM (οι selectors φαίνονται στο admin, Domains -> DNS records)"
fi

MTASTS="$(txt "_mta-sts.$DOMAIN" | grep -i '^v=STSv1')"
if [[ -n "$MTASTS" ]]; then
  ok "MTA-STS TXT: $MTASTS"
  POL="$(curl -fsS --max-time 8 "https://mta-sts.$DOMAIN/.well-known/mta-sts.txt" 2>/dev/null)"
  [[ -n "$POL" ]] && ok "MTA-STS policy: $(tr '\n' ' ' <<<"$POL")" || bad "https://mta-sts.$DOMAIN/.well-known/mta-sts.txt δεν απαντά (cert/CNAME;)"
else warn "Χωρίς MTA-STS (προαιρετικό, συνιστάται)"; fi

TLSRPT="$(txt "_smtp._tls.$DOMAIN" | grep -i '^v=TLSRPTv1')"
[[ -n "$TLSRPT" ]] && ok "TLS-RPT: $TLSRPT" || warn "Χωρίς TLS-RPT (_smtp._tls.$DOMAIN)"

for s in _submissions._tcp _imaps._tcp; do
  v="$(dig +short SRV "$s.$DOMAIN" $R)"
  [[ -n "$v" ]] && ok "SRV $s -> $v" || warn "Χωρίς SRV $s (βοηθά το auto-config των clients)"
done

echo
[[ $FAIL -eq 0 ]] && echo "DNS εντάξει." || { echo "Υπάρχουν λάθη στο DNS."; exit 1; }
