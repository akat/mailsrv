# mailsrv: Stalwart Mail Server σε Docker

Mail server για παραγωγή, σε ένα container: SMTP, IMAP, JMAP, ManageSieve, anti-spam και web διαχειριστικό.
Βασίζεται στο [Stalwart](https://stalw.art) **v1.1.1**. Υποστηρίζει DKIM (RSA και Ed25519), SPF, DMARC, ARC, MTA-STS,
TLS-RPT, DANE και αυτόματα πιστοποιητικά Let's Encrypt.

Υπάρχουν δύο τρόποι εγκατάστασης:

- **Standalone** (`docker-compose.yml`): ο Stalwart έχει όλο τον server, μαζί με τις θύρες 80/443. Ακολούθησε αυτό το README.
- **Portainer + κοινός Traefik** (`portainer-stack.yml`): ο Traefik κρατά τις 80/443 και ο Stalwart ανοίγει μόνο τις θύρες mail. Δες το **[PORTAINER.md](PORTAINER.md)**.

```
docker-compose.yml     standalone: ένα service, network_mode: host, δύο named volumes
portainer-stack.yml    Portainer stack πίσω από Traefik (network proxy, resolver le)
PORTAINER.md           οδηγός για το Portainer/Traefik σενάριο
.env.example           έκδοση, hostname, (προαιρετικός) recovery admin
scripts/preflight.sh   έλεγχοι server πριν το πρώτο up (PTR, θύρα 25, blacklists, ελεύθερες θύρες)
scripts/check-dns.sh   έλεγχος MX/SPF/DKIM/DMARC/MTA-STS/TLS-RPT/SRV
scripts/firewall.sh    κανόνες ufw
scripts/backup.sh      cold backup των volumes και οδηγίες επαναφοράς
```

---

## 1. Πριν από όλα: το deliverability το κρίνει κυρίως η υποδομή

Το λογισμικό δεν αρκεί. Τα μηνύματα πάνε στα spam κυρίως όταν λείπει κάτι από τα παρακάτω:

| Απαίτηση | Γιατί |
|---|---|
| **VPS / dedicated με σταθερή δημόσια IP**. Όχι οικιακή γραμμή, όχι αυτό το WSL | Οι οικιακές IP είναι μόνιμα στο Spamhaus PBL |
| **Ανοιχτή εξερχόμενη θύρα 25** | Hetzner, AWS, GCP, Azure, DigitalOcean την κλειδώνουν από προεπιλογή. Ζήτα unblock |
| **PTR (reverse DNS) της IP = `mail.example.com`** | Χωρίς σωστό FCrDNS, Gmail και Outlook απορρίπτουν ή στέλνουν στα spam. Ρυθμίζεται στο panel του παρόχου |
| **IP εκτός blacklists** | Έλεγξε στο https://check.spamhaus.org και στο https://mxtoolbox.com/blacklists.aspx |
| **IPv6**: ή PTR και για την IPv6, ή καθόλου IPv6 | Με host networking ο server στέλνει και από IPv6. Το Gmail είναι πολύ αυστηρό εκεί |

Πόροι: 2 vCPU / 4 GB RAM για μερικές δεκάδες mailboxes. Ο δίσκος εξαρτάται από τον όγκο των μηνυμάτων.

## 2. Εγκατάσταση στον server

```bash
# στον server (Debian/Ubuntu με Docker Engine και το compose plugin)
sudo mkdir -p /opt/mailsrv && sudo chown $USER /opt/mailsrv
# αντέγραψε τα αρχεία του repo στο /opt/mailsrv
cd /opt/mailsrv
cp .env.example .env && chmod 600 .env
nano .env                                  # STALWART_HOSTNAME=mail.<domain>

./scripts/preflight.sh                     # πρέπει να βγάλει "Όλα εντάξει"
sudo ./scripts/firewall.sh                 # SSH_PORT=2222 sudo ... αν το SSH δεν είναι στη 22
docker compose up -d
docker compose logs stalwart | grep -A3 username   # προσωρινός κωδικός admin
```

## 3. Αρχική ρύθμιση (setup wizard)

Η θύρα 8080 είναι κλειστή στο firewall, οπότε η πρόσβαση γίνεται με SSH tunnel από τον δικό σου υπολογιστή:

```bash
ssh -L 8080:127.0.0.1:8080 user@mail.example.com
# browser: http://localhost:8080/admin  -> admin / <κωδικός από τα logs>
```

Στον wizard:

- **Hostname**: `mail.example.com`. Ίδιο με το PTR και το `.env`.
- **Default domain**: `example.com`
- **Request TLS certificate**: ✅. Το Let's Encrypt εκδίδει πιστοποιητικό με το `tls-alpn-01` στη θύρα 443, που πρέπει να είναι ανοιχτή και να μη την έχει πιάσει άλλος web server.
- **Generate DKIM keys**: ✅
- **Stores**: άφησε τα defaults (RocksDB). Είναι το σωστό για έναν κόμβο.
- **DNS server**: αν ο DNS πάροχος υποστηρίζεται (π.χ. Cloudflare), δώσε API token και ο Stalwart θα γράφει μόνος του τα records. Αλλιώς τα περνάς χειροκίνητα (βήμα 4).

Στο τέλος ο wizard φτιάχνει τον μόνιμο διαχειριστή. **Αποθήκευσε τον κωδικό σε password manager.**
Μετά την ολοκλήρωση το admin είναι διαθέσιμο και στο `https://mail.example.com/admin`.

Για break-glass πρόσβαση μπορείς να ορίσεις `STALWART_RECOVERY_ADMIN=admin:<τυχαίος κωδικός>` στο `.env` και να τρέξεις `docker compose up -d`.

## 4. DNS records

Στο admin, στο **Domains → example.com → DNS records**, εμφανίζονται τα **ακριβή** records, μαζί με τα DKIM public keys.
Χρησιμοποίησε αυτά. Ο πίνακας από κάτω είναι η αναμενόμενη μορφή τους (IP `203.0.113.10`):

| Τύπος | Όνομα | Τιμή |
|---|---|---|
| A | `mail.example.com` | `203.0.113.10` |
| AAAA | `mail.example.com` | IPv6, μόνο αν έχει και PTR |
| PTR | `203.0.113.10` | `mail.example.com` (**στον πάροχο του VPS**) |
| MX | `example.com` | `10 mail.example.com` |
| TXT | `example.com` | `v=spf1 mx -all` |
| TXT | `mail.example.com` | `v=spf1 a -all` (SPF για το HELO) |
| TXT | `<selector>._domainkey.example.com` | από το admin (δύο records: RSA και Ed25519) |
| TXT | `_dmarc.example.com` | `v=DMARC1; p=none; rua=mailto:dmarc@example.com; adkim=s; aspf=s` |
| CNAME | `mta-sts.example.com` | `mail.example.com` |
| TXT | `_mta-sts.example.com` | `v=STSv1; id=<από admin>` |
| TXT | `_smtp._tls.example.com` | `v=TLSRPTv1; rua=mailto:tls-reports@example.com` |
| CNAME | `autoconfig.example.com`, `autodiscover.example.com` | `mail.example.com` |
| SRV | `_submissions._tcp.example.com` | `0 1 465 mail.example.com` |
| SRV | `_imaps._tcp.example.com` | `0 1 993 mail.example.com` |
| CAA | `example.com` | `0 issue "letsencrypt.org"` |

Το πιστοποιητικό πρέπει να καλύπτει και τα `mta-sts.`, `autoconfig.` και `autodiscover.`.
Έλεγξέ το στο admin (TLS / ACME) αφού δημιουργηθούν τα CNAME.

Δημιούργησε τα mailboxes ή aliases `postmaster@`, `abuse@`, `dmarc@` και `tls-reports@`.
Τα δύο πρώτα τα απαιτούν τα RFC, και τα κοιτάνε οι μεγάλοι πάροχοι.

Επαλήθευση:

```bash
DKIM_SELECTORS="<sel1> <sel2>" ./scripts/check-dns.sh example.com mail.example.com
```

## 5. Πριν βγει σε παραγωγή

1. **Δοκιμή βαθμολογίας**: στείλε email στη διεύθυνση που δίνει το https://www.mail-tester.com. Στόχος 10/10.
   Επίσης στείλε σε λογαριασμό Gmail και δες *Show original*: SPF, DKIM και DMARC πρέπει να είναι όλα `PASS`.
2. **Εγγραφή στα εργαλεία των παρόχων**:
   - Google Postmaster Tools: https://postmaster.google.com (reputation, spam rate)
   - Microsoft SNDS και JMRP: https://sendersupport.olc.protection.outlook.com/snds/
3. **Warm-up**: μια νέα IP ή ένα νέο domain δεν έχει reputation. Ξεκίνα με λίγες δεκάδες μηνύματα τη μέρα προς ανθρώπους που απαντούν, και ανέβαινε σταδιακά μέσα σε 2-4 εβδομάδες. **Μη στέλνεις μαζικά newsletters** από αυτόν τον server. Για αυτά χρησιμοποίησε ESP με ξεχωριστό subdomain.
4. **DMARC**: μετά από περίπου 2 εβδομάδες καθαρών reports (μόνο οι δικές σου πηγές περνάνε), άλλαξε σε `p=quarantine` και μετά σε `p=reject`.
   Αν άλλες υπηρεσίες στέλνουν για λογαριασμό του domain (CRM, ticketing, Google Workspace κ.λπ.), πρόσθεσέ τες στο SPF και ρύθμισε DKIM και σε αυτές **πριν** το reject.
5. **MTA-STS**: ξεκινά σε `testing`. Όταν τα TLS reports είναι καθαρά, άλλαξε σε `enforce` από το admin και ανέβασε το `id`.

## 6. Λειτουργία

| Εργασία | Εντολή |
|---|---|
| Logs | `docker compose logs -f stalwart` (και στο admin: Telemetry / Logs) |
| Κατάσταση | `docker compose ps` (έχει ενσωματωμένο healthcheck) |
| Backup | `./scripts/backup.sh` (στο `./backups`, ή όπου δείχνει το `BACKUP_DIR`), και στο cron: `15 3 * * * /opt/mailsrv/scripts/backup.sh >> /opt/mailsrv/backups/backup.log 2>&1` |
| Off-site | συγχρόνισε το `backups/` εκτός server (restic/borg/rclone). Ένα backup μόνο στον ίδιο δίσκο δεν προστατεύει από απώλεια του server |
| Αναβάθμιση | διάβασε τα release notes, τρέξε `./scripts/backup.sh`, άλλαξε `STALWART_VERSION` στο `.env`, και μετά `docker compose pull && docker compose up -d` |

Ασφάλεια:

- Ενεργοποίησε **2FA** για τον admin και για τους χρήστες (υποστηρίζεται TOTP).
- Οι χρήστες ρυθμίζουν clients μόνο σε **465/587 (submission)** και **993 (IMAPS)**. Η θύρα 25 δεν δέχεται authentication από clients.
- Ο Stalwart έχει ενσωματωμένο auto-ban για brute-force, οπότε δεν χρειάζεται fail2ban.
- Για επιπλέον προστασία μπορείς να περιορίσεις το `/admin` σε συγκεκριμένες IP από το admin (HTTP access control) ή να το χρησιμοποιείς μόνο μέσω SSH tunnel.

Webmail: ο Stalwart δεν έχει δικό του. Οι χρήστες συνδέονται με Thunderbird, Outlook ή κινητό (auto-config μέσω των records του βήματος 4).
Αν χρειάζεσαι webmail, πρόσθεσε π.χ. Roundcube ή SnappyMail σε ξεχωριστό host (`webmail.example.com`) πίσω από reverse proxy.
Χρειάζεται προσοχή, γιατί η θύρα 443 ανήκει στον Stalwart (ACME tls-alpn-01).
