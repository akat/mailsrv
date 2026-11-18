# Εγκατάσταση μέσω Portainer, πίσω από τον κοινό Traefik

> Για νέα εγκατάσταση με απλά βήματα δες το **[INSTALL.md](INSTALL.md)**. Εδώ είναι η τεχνική τεκμηρίωση.

Αρχείο stack: [portainer-stack.yml](portainer-stack.yml). Για τα γενικά (deliverability, DNS records, go-live), δες το [README](README.md).
Εδώ είναι μόνο ό,τι αλλάζει όταν υπάρχει ήδη Traefik (network `proxy`, resolver `le`, entrypoint `websecure`).

## Πώς στήνεται

```
Internet ──443──> Traefik ──(proxy network)──> stalwart:8080   admin, JMAP, autoconfig, MTA-STS
Internet ──443──> Traefik ──(proxy network)──> snappymail:8888 ──(mailnet)──> stalwart:993/465/4190   webmail
SSH tunnel ──> 127.0.0.1:18080 ────────────────> stalwart:8080   ΜΟΝΟ για τον αρχικό wizard / έκτακτη ανάγκη
Internet ──25/465/993/4190 (IPv4)──────────> stalwart       SMTP / IMAP / Sieve, απευθείας
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
   | `STALWART_RECOVERY_ADMIN` | προαιρετικό, π.χ. `admin:Xk3...` (χωρίς `<` `>`) |

4. **Deploy the stack**.
5. **Containers → stalwart → Logs**: κράτα τον προσωρινό κωδικό του `admin`. Τυπώνεται μία φορά.

### 3. Setup wizard: μέσω SSH tunnel, ΟΧΙ μέσω Traefik

Στο bootstrap mode (πριν ολοκληρωθεί ο wizard), ο Stalwart απαιτεί το URL του browser να έχει το ίδιο scheme με τη σύνδεση που δέχεται.
Μέσω Traefik ο browser είναι σε `https`, αλλά ο Stalwart δέχεται `http`, οπότε το login αποτυγχάνει με **"Client metadata documents are disabled"**.
Γι' αυτό τον wizard τον κάνεις μέσω SSH tunnel. Το stack ανοίγει την 8080 **μόνο** στο `127.0.0.1` του server:

```bash
ssh -L 8080:127.0.0.1:18080 user@server
# browser: http://localhost:8080/admin  ->  admin / <κωδικός από τα logs ή το STALWART_RECOVERY_ADMIN>
```

Στον wizard:

- **Hostname**: `mail.example.com`. **Default domain**: `example.com`.
- **DNS server**: διάλεξε τον DNS πάροχό σου και δώσε API token. Για Cloudflare: token με `Zone → DNS → Edit` μόνο για τη συγκεκριμένη zone. Υποστηρίζονται και Route53, DigitalOcean, OVH, Hetzner, Porkbun, Google Cloud DNS, Azure, deSEC και άλλοι.
  Με DNS provider ο wizard ρυθμίζει αυτόματα το ACME σε **DNS-01** και μπορεί να γράφει μόνος του τα DKIM/SPF/DMARC/MTA-STS records.
- **Request TLS certificate**: ✅. **Generate DKIM keys**: ✅. **Stores**: defaults (RocksDB).
- **Logging / Tracer**: διάλεξε **Stdout (console)**. Η προεπιλογή γράφει σε αρχείο μέσα στο container (`/var/log/stalwart`, όχι volume), και τότε το Portainer → Logs μένει **άδειο**.

Στο τέλος ο wizard δείχνει τον **μόνιμο** admin (`admin@<domain>`) και τον κωδικό του. Αποθήκευσέ τον αμέσως.
Μετά κάνε **restart** το container (Portainer → Containers → stalwart → Restart). Μόνο τότε ο server βγαίνει από το bootstrap mode και ανοίγει τις θύρες mail.
Από εκεί και πέρα το admin είναι στο **`https://mail.example.com/admin`** μέσω Traefik. Το tunnel μένει για έκτακτη ανάγκη.

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

## Επιπλέον domains στον ίδιο server

Κάθε επιπλέον domain χρησιμοποιεί τον ίδιο mail server (`MAIL_HOSTNAME`). Δεν χρειάζεται νέα IP, PTR ή cert για SMTP/IMAP. Οι clients συνδέονται στο `mail.example.com`.

1. **Portainer:** πρώτα βάλε τα 4 CNAME του πίνακα παρακάτω, αλλιώς ο Traefik θα αποτύχει να βγάλει cert. Μετά, στο stack, βάλε `MAIL_EXTRA_DOMAIN_1=example.net` (και `_2` για δεύτερο) και κάνε **Update the stack**. Αυτό φτιάχνει τα Traefik routes για MTA-STS/autoconfig και ρυθμίζει το webmail για το νέο domain.
2. **Stalwart admin:** πρόσθεσε το domain και τους λογαριασμούς. Ο Stalwart βγάζει DKIM και δείχνει τα DNS records που χρειάζεται.
3. **DNS** του νέου domain, όλα **DNS only**:

   | Type | Name | Content |
   |---|---|---|
   | CNAME | `mta-sts`, `autoconfig`, `autodiscover`, `ua-auto-config` | `mail.example.com` |
   | TXT | DKIM, `_mta-sts`, `_smtp._tls` | ό,τι δείχνει ο Stalwart |
   | TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:postmaster@example.net` |
   | MX | `@` | `mail.example.com` (**τελευταίο**, βλ. παρακάτω) |
   | TXT | `@` (SPF) | `v=spf1 mx -all` (**μαζί** με το MX) |

   Χωρίς A record `mail.example.net`.
4. **Webmail:** οι χρήστες του νέου domain μπαίνουν στο ίδιο `https://webmail.<MAIL_DOMAIN>`.

### Αν το domain έχει ήδη email σε άλλη υπηρεσία (Zoho, Google κ.λπ.)

Η αλλαγή του MX είναι η στιγμή που αλλάζει η λήψη. Η σειρά μετράει:

1. Μια μέρα πριν, κατέβασε το **TTL του MX** στα 5 λεπτά.
2. Φτιάξε στον Stalwart **όλους** τους λογαριασμούς και τα aliases που υπάρχουν στον παλιό πάροχο. Mail προς διεύθυνση που λείπει θα γυρίσει πίσω.
3. **Πρώτη αντιγραφή** των mailbox από τον παλιό πάροχο με `imapsync` (βλ. παρακάτω). Ο παλιός πάροχος συνεχίζει να λαμβάνει κανονικά.
4. **Αλλαγή MX + SPF.** Για μερικές μέρες κράτα στο SPF και τον παλιό πάροχο (π.χ. `v=spf1 mx include:zohomail.eu ~all`), για όσους στέλνουν ακόμα από εκεί.
5. Μετά από 1–2 ώρες, **δεύτερη αντιγραφή** με `imapsync`. Παίρνει μόνο ό,τι ήρθε στο ενδιάμεσο.
6. Ρύθμισε ξανά τους clients (Outlook, κινητά) με server `mail.example.com`, θύρες 993/465.
7. Κλείσε τον παλιό πάροχο μόνο όταν βεβαιωθείς ότι δεν λείπει τίποτα, και βγάλε το `include:` από το SPF.

Αντιγραφή ενός mailbox (από τον server, μία φορά ανά λογαριασμό):

```bash
docker run --rm --network host gilleslamiral/imapsync imapsync \
  --host1 imappro.zoho.eu --port1 993 --ssl1 --user1 info@example.net --password1 'ΚΩΔΙΚΟΣ_ZOHO' \
  --host2 127.0.0.1      --port2 993 --ssl2 --user2 info@example.net --password2 'ΚΩΔΙΚΟΣ_STALWART' \
  --sslargs2 SSL_verify_mode=0 --automap
```

Στο Zoho, αν έχει 2FA, χρειάζεται **app password** και πρέπει να είναι ενεργό το IMAP access (Settings → Mail Accounts → IMAP). Τρέξε την ίδια εντολή και τις δύο φορές. Το `imapsync` δεν αντιγράφει δεύτερη φορά ό,τι υπάρχει ήδη.

## Webmail (SnappyMail): `https://webmail.<MAIL_DOMAIN>`

Το stack περιλαμβάνει το SnappyMail. Συνδέεται στον Stalwart μέσα από το ιδιωτικό δίκτυο `mailnet` (IMAPS 993, SMTPS 465, Sieve 4190), χωρίς να ανοίγει νέες θύρες.
Το domain `MAIL_DOMAIN` ρυθμίζεται αυτόματα σε κάθε εκκίνηση. Το admin panel του SnappyMail (`/?admin`) είναι κλειστό.

1. **Cloudflare:** `CNAME webmail -> mail.<domain>`, **DNS only**. Το cert το βγάζει ο Traefik.
2. **Stalwart admin → Security → Allowed IPs:** πρόσθεσε το `10.253.53.0/28`, ή ό,τι έχεις στο `MAILNET_SUBNET`.
   Όλοι οι χρήστες του webmail φαίνονται στον Stalwart να έρχονται από την IP του container του SnappyMail. Χωρίς αυτή τη ρύθμιση, λάθος κωδικοί ενός χρήστη μπορεί να ενεργοποιήσουν το auto-ban και να **κλειδώσουν το webmail για όλους**.
   Το αντίτιμο: ο Stalwart δεν μπορεί να κόψει brute-force που γίνεται *μέσω* webmail. Γι' αυτό χρειάζονται δυνατοί κωδικοί και 2FA.
3. **Login** με το πλήρες email (`info@<domain>`) και τον κωδικό του λογαριασμού στον Stalwart.

| Μεταβλητή | Default | |
|---|---|---|
| `SNAPPYMAIL_VERSION` | `v2.38.2.1` | έκδοση image (`djmaze/snappymail`) |
| `SNAPPYMAIL_ADMIN_PANEL` | `Off` | `On` μόνο προσωρινά, αν χρειαστεί. Ο κωδικός είναι στο `/var/lib/snappymail/_data_/_default_/admin_password.txt` |
| `MAILNET_SUBNET` | `10.253.53.0/28` | άλλαξέ το αν συγκρούεται με υπάρχον δίκτυο του server |

Το TLS verify από το SnappyMail προς τον Stalwart είναι κλειστό. Η σύνδεση είναι container προς container μέσα στο `mailnet`, και ο Stalwart έχει self-signed cert μέχρι να βγει το Let's Encrypt.

## Λειτουργία

| Εργασία | Πώς |
|---|---|
| Logs | Portainer → Containers → stalwart → Logs |
| Backup | με το image εργαλείων (βλ. παρακάτω), από cron στον host. Βρίσκει μόνο του τα volumes του stack (`mail_stalwart-*`) |
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

## Image εργαλείων: `ghcr.io/<owner>/mailsrv-tools`

Το GitHub Action ([.github/workflows/ci.yml](.github/workflows/ci.yml)) κάνει τα εξής σε κάθε push στο `main`:

1. Τρέχει shellcheck στα scripts και validation και στα δύο compose αρχεία.
2. Χτίζει το image εργαλείων από το [tools/Dockerfile](tools/Dockerfile). Έχει τα scripts μαζί με `dig`, `nc`, `curl`, `ss` και Docker CLI.
3. Κάνει smoke test και, μόνο αν περάσει, push στο GHCR ως `latest` και `sha-xxxxxxx`, για amd64 και arm64.
4. Προαιρετικά, ζητά από το Portainer redeploy του stack (βλ. GitOps παρακάτω).

**Ο mail server τρέχει πάντα το επίσημο `stalwartlabs/stalwart`.** Το image εργαλείων δεν τρέχει μόνιμα. Το καλείς όποτε το χρειάζεσαι:

```bash
T=ghcr.io/<owner>/mailsrv-tools:latest

# Έλεγχος DNS (από οπουδήποτε)
docker run --rm -e DKIM_SELECTORS="sel1 sel2" $T check-dns example.com mail.example.com

# Preflight (στον server, με host network για να βλέπει θύρες και την IP του)
docker run --rm --network host -e MODE=traefik $T preflight mail.example.com

# Backup. Το BACKUP_DIR πρέπει να γίνει mount στο ΙΔΙΟ path μέσα και έξω
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/backups/stalwart:/opt/backups/stalwart \
  -e BACKUP_DIR=/opt/backups/stalwart -e BACKUP_OWNER=1000:1000 \
  $T backup
```

Cron στον host για καθημερινό backup στις 03:15:

```cron
15 3 * * * docker run --rm --pull always -v /var/run/docker.sock:/var/run/docker.sock -v /opt/backups/stalwart:/opt/backups/stalwart -e BACKUP_DIR=/opt/backups/stalwart ghcr.io/<owner>/mailsrv-tools:latest backup >> /var/log/stalwart-backup.log 2>&1
```

Το backup έχει πρόσβαση στο `docker.sock`, δηλαδή ισοδυναμεί με root στον host. Γι' αυτό είναι ξεχωριστό, προσωρινό container και όχι μέρος του mail server.
Αν το repo είναι private, το package στο GHCR είναι επίσης private. Κάνε στον server `docker login ghcr.io` με PAT που έχει `read:packages`.

## GitOps: deploy του stack από το git

Αντί για copy-paste στο Web editor:

1. **Stacks → Add stack → Repository**:
   - URL του repo, reference `refs/heads/main`, compose path `portainer-stack.yml`.
   - Για private repo: authentication με PAT (fine-grained, `Contents: read`).
2. Τα env vars (`MAIL_HOSTNAME` κ.λπ.) μπαίνουν στο Portainer όπως πριν. **Δεν μπαίνουν στο git.**
3. Ενεργοποίησε το **GitOps updates**. Υπάρχουν δύο τρόποι:
   - **Polling** (π.χ. κάθε 5 λεπτά): δεν χρειάζεται τίποτα άλλο.
   - **Webhook**: αντέγραψε το URL που δίνει το Portainer και βάλ' το ως repo secret `PORTAINER_WEBHOOK_URL` στο GitHub (*Settings → Secrets and variables → Actions*). Το job `deploy` θα το καλεί αφού περάσει το CI. Έτσι αλλαγή που δεν περνά το validation δεν φτάνει ποτέ στον server.
4. **Μην ενεργοποιήσεις το "Re-pull image" στο GitOps.** Η έκδοση του Stalwart αλλάζει μόνο όταν αλλάξεις εσύ το `STALWART_VERSION`, αφού κάνεις backup.
