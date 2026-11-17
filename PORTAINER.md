# Εγκατάσταση μέσω Portainer, πίσω από τον κοινό Traefik

Αρχείο stack: [portainer-stack.yml](portainer-stack.yml). Για τα γενικά (deliverability, DNS records, go-live), δες το [README](README.md).
Εδώ είναι μόνο ό,τι αλλάζει όταν υπάρχει ήδη Traefik (network `proxy`, resolver `le`, entrypoint `websecure`).

## Πώς στήνεται

```
Internet ──443──> Traefik ──(proxy network)──> stalwart:8080   admin, JMAP, autoconfig, MTA-STS
Internet ──25/465/587/993/4190 (IPv4)──────────> stalwart       SMTP / IMAP / Sieve, απευθείας
```

- **Ο Traefik δεν μπαίνει μπροστά από τις θύρες mail.** Αν έμπαινε, ο Stalwart δεν θα έβλεπε την πραγματική IP των αποστολέων, και τότε δεν δουλεύουν SPF, DNSBL, rate limit και auto-ban.
- **Το cert για SMTP/IMAP το βγάζει ο ίδιος ο Stalwart με ACME DNS-01.** Η 443 ανήκει στον Traefik, οπότε το TLS-ALPN-01 που χρησιμοποιεί ο Stalwart από προεπιλογή δεν δουλεύει. Τα certs των web hostnames τα βγάζει ο Traefik (`le`).
- **Μόνο IPv4.** Το `MAIL_HOSTNAME` **δεν** πρέπει να έχει AAAA record. Έτσι δεν χρειάζεται PTR για IPv6 και οι εισερχόμενες συνδέσεις έρχονται πάντα με την πραγματική IP.
- **Το Watchtower είναι απενεργοποιημένο για αυτό το container.** Ο mail server δεν πρέπει να αναβαθμίζεται μόνος του.

## Βήματα

### 1. Προετοιμασία στον host

```bash
MODE=traefik ./scripts/preflight.sh mail.example.com
```

Ελέγχει PTR, την εξερχόμενη θύρα 25, blacklists, ελεύθερες θύρες και ότι δεν υπάρχει AAAA. Πρέπει να περάσουν όλα.

DNS πριν το deploy:

- `A mail.example.com -> <IP>`
- `CNAME mta-sts / autoconfig / autodiscover -> mail.example.com`

Τα θέλει ο Traefik για να βγάλει certs.
**Αν ο DNS είναι στο Cloudflare: το `mail.example.com` πρέπει να είναι DNS only (γκρι σύννεφο), όχι proxied.** Το Cloudflare δεν περνά SMTP/IMAP.

### 2. Stack στο Portainer

1. **Stacks → Add stack**, όνομα π.χ. `mail`.
2. Επικόλλησε το `portainer-stack.yml` στο Web editor, ή διάλεξε *Repository* αν το βάλεις σε git.
3. Στο **Environment variables** (ή *Load variables from .env file* με το [portainer-stack.env.example](portainer-stack.env.example)):

   | Μεταβλητή | Τιμή |
   |---|---|
   | `MAIL_HOSTNAME` | `mail.example.com` |
   | `MAIL_DOMAIN` | `example.com` |
   | `STALWART_VERSION` | `v1.1.1` |
   | `TZ` | `Europe/Athens` |
   | `STALWART_RECOVERY_ADMIN` | προαιρετικό, `admin:<τυχαίος κωδικός>` |

4. **Deploy the stack**.
5. **Containers → stalwart → Logs**: κράτα τον προσωρινό κωδικό του `admin`. Τυπώνεται μία φορά.

### 3. Setup wizard: `https://mail.example.com/admin`

- **Hostname**: `mail.example.com`. **Default domain**: `example.com`.
- **DNS server**: διάλεξε τον DNS πάροχό σου και δώσε API token. Για Cloudflare: token με `Zone → DNS → Edit` μόνο για τη συγκεκριμένη zone. Υποστηρίζονται και Route53, DigitalOcean, OVH, Hetzner, Porkbun, Google Cloud DNS, Azure, deSEC και άλλοι.
  Με DNS provider ο wizard ρυθμίζει αυτόματα το ACME σε **DNS-01** και μπορεί να γράφει μόνος του τα DKIM/SPF/DMARC/MTA-STS records.
- **Request TLS certificate**: ✅. **Generate DKIM keys**: ✅. **Stores**: defaults (RocksDB).

**Αν ο DNS πάροχος δεν υποστηρίζεται**, χρησιμοποίησε HTTP-01 μέσω Traefik:

1. Στον wizard άφησε το DNS server σε *Manual* και ξετσέκαρε το TLS.
2. Ξεσχολίασε τα 4 labels `stalwart-acme` στο stack. Βάλε το όνομα του entrypoint :80 του Traefik σου, που είναι συνήθως `web`.
3. Στο admin, στο **TLS → ACME providers**, πρόσθεσε Let's Encrypt με challenge **HTTP-01** για το `mail.example.com`.

Αυτό δεν δουλεύει αν ο resolver `le` του Traefik χρησιμοποιεί `httpChallenge`, γιατί τότε ο Traefik κρατά για τον εαυτό του τα `/.well-known/acme-challenge/`. Τότε το DNS-01 είναι μονόδρομος.

### 4. Αμέσως μετά τον wizard: πραγματική IP πίσω από Traefik

**Settings → HTTP**:

- **Client IP source** = `X-Forwarded-For`
- **Forwarded hops** = `1`

Χωρίς αυτό, ο Stalwart βλέπει όλα τα HTTP requests να έρχονται από τον Traefik. Μετά από μερικές λάθος συνδέσεις, το auto-ban **θα μπλοκάρει την IP του Traefik**, και κανείς δεν θα μπορεί να μπει στο admin ή στο JMAP.

Μετά συνέχισε από το [README §4](README.md#4-dns-records) (DNS records) και το [§5](README.md#5-πριν-βγει-σε-παραγωγή) (mail-tester, Postmaster Tools, warm-up, DMARC).
Η μόνη διαφορά: **χωρίς AAAA**.

## Λειτουργία

| Εργασία | Πώς |
|---|---|
| Logs | Portainer → Containers → stalwart → Logs |
| Backup | στον host, με cron: `15 3 * * * BACKUP_DIR=/opt/backups/stalwart /opt/mailsrv/scripts/backup.sh >> /opt/backups/stalwart/backup.log 2>&1`. Βρίσκει μόνο του τα volumes του stack (`mail_stalwart-*`) |
| Off-site | συγχρόνισε το `BACKUP_DIR` εκτός server (restic/borg/rclone) |
| Αναβάθμιση | διάβασε τα release notes, κάνε backup, άλλαξε `STALWART_VERSION` στις env vars του stack και πάτα **Update the stack** με *Re-pull image* |
| Firewall | Το Docker ανοίγει μόνο του τις published θύρες, παρακάμπτοντας το ufw. Η 8080 **δεν** γίνεται publish, οπότε φτάνει μόνο ο Traefik. Το `scripts/firewall.sh` είναι για το standalone σενάριο. **Μην το τρέξεις** σε host με άλλα services χωρίς να το ελέγξεις |

### Προαιρετικό: περιορισμός του `/admin` σε συγκεκριμένες IP

Ο Stalwart έχει δικό του login, 2FA και auto-ban. Αν θέλεις και περιορισμό δικτύου, βάλε ξεχωριστό router για το `/admin` με IP allowlist στον Traefik.
Η σύνταξη είναι για Traefik v3. Στη v2 το middleware λέγεται `ipwhitelist`.

```yaml
      - "traefik.http.routers.stalwart-admin.rule=Host(`${MAIL_HOSTNAME}`) && PathPrefix(`/admin`)"
      - "traefik.http.routers.stalwart-admin.entrypoints=websecure"
      - "traefik.http.routers.stalwart-admin.tls.certresolver=le"
      - "traefik.http.routers.stalwart-admin.service=stalwart"
      - "traefik.http.routers.stalwart-admin.middlewares=stalwart-admin-ip"
      - "traefik.http.middlewares.stalwart-admin-ip.ipallowlist.sourcerange=203.0.113.0/24,198.51.100.7/32"
```
