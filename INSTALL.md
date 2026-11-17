# Νέα εγκατάσταση mail server: βήμα προς βήμα

Ο οδηγός στήνει **email για ένα domain** (π.χ. `info@example.gr`) με webmail, σε server που έχει ήδη **Portainer** και **Traefik**.
Παντού όπου βλέπεις `example.gr`, βάλε το δικό σου domain.

**Χρόνος:** περίπου 1 ώρα δουλειά. Μετράει όμως και η αναμονή για τη Hetzner (βήμα 1), που μπορεί να πάρει μέρες.

---

## Τι χρειάζεσαι πριν ξεκινήσεις

- **Server στη Hetzner** με Portainer και Traefik. Ο Traefik πρέπει να έχει δίκτυο `proxy` και resolver `le`.
- **Το domain στο Cloudflare.**
- **Το αρχείο `portainer-stack.yml`** από αυτό το repo.
- **Ένα password manager.** Θα φτιάξεις αρκετούς κωδικούς.

---

## Βήμα 1: Ζήτα από τη Hetzner να ανοίξει τη θύρα 25 (κάν' το ΠΡΩΤΟ)

Η Hetzner μπλοκάρει την **αποστολή** email από καινούριους servers. Χωρίς αυτό το βήμα ο server θα **λαμβάνει** email, αλλά **δεν θα στέλνει**.
Η έγκριση αργεί, γι' αυτό ξεκινάς από εδώ.

1. Hetzner Console → **Support** → νέο αίτημα για ports / "Sending mails".
2. Γράψε κάτι σαν:
   > Please unblock outgoing port 25 for server `<IP>`. It runs a mail server for our own domain example.gr, with reverse DNS mail.example.gr, SPF, DKIM and DMARC. No bulk email.
3. Η Hetzner συνήθως εγκρίνει μετά την **πρώτη πληρωμένη χρέωση** του λογαριασμού.

---

## Βήμα 2: Cloudflare, τα πρώτα DNS records

Cloudflare → το domain σου → **DNS → Records → Add record**.

**Όλα με γκρι σύννεφο ("DNS only"), ΟΧΙ πορτοκαλί.** Με πορτοκαλί, τα email δεν φτάνουν ποτέ στον server.

| Type | Name | Content |
|---|---|---|
| A | `mail` | η IP του server |
| CNAME | `webmail` | `mail.example.gr` |
| CNAME | `mta-sts` | `mail.example.gr` |
| CNAME | `autoconfig` | `mail.example.gr` |
| CNAME | `autodiscover` | `mail.example.gr` |
| CNAME | `ua-auto-config` | `mail.example.gr` |

**Μην** βάλεις AAAA (IPv6) για το `mail`.

---

## Βήμα 3: Hetzner, reverse DNS

Αυτό ρυθμίζεται στη **Hetzner**, όχι στο Cloudflare, γιατί αφορά την IP και όχι το domain.
Χωρίς αυτό, τα email σου πάνε στα spam.

1. Hetzner Console → **Servers** → ο server σου → καρτέλα **Networking**.
2. Στην **Primary IPv4** → **Edit Reverse DNS** → γράψε `mail.example.gr` → Save.

---

## Βήμα 4: Portainer, το stack

1. Φτιάξε έναν τυχαίο κωδικό για τον «λογαριασμό ανάκτησης» και κράτα τον στο password manager. Τον χρειάζεσαι στο βήμα 5.
   Χρησιμοποίησε **μόνο γράμματα και αριθμούς**, περίπου 24 χαρακτήρες. Από WSL ή Linux:
   ```
   openssl rand -base64 18 | tr -dc 'A-Za-z0-9'
   ```
2. Portainer → **Stacks → Add stack**, με όνομα `mail`.
3. Επικόλλησε όλο το `portainer-stack.yml` στο **Web editor**.
4. Στο **Environment variables** πρόσθεσε:

   | Name | Value |
   |---|---|
   | `MAIL_HOSTNAME` | `mail.example.gr` |
   | `MAIL_DOMAIN` | `example.gr` |
   | `STALWART_RECOVERY_ADMIN` | `admin:` + τον κωδικό, π.χ. `admin:Xk3m9Qw2...`. **Χωρίς** `<` `>`, χωρίς κενά |

5. **Deploy the stack.**

**Αν βγει σφάλμα:**
- `port is already allocated` για την **8080**: πρόσθεσε μεταβλητή `ADMIN_LOCAL_PORT` = `18081` (ή άλλη ελεύθερη θύρα) και ξανακάνε Deploy.
- `Pool overlaps`: πρόσθεσε `MAILNET_SUBNET` = `10.253.54.0/28` και ξανακάνε Deploy.

---

## Βήμα 5: Αρχική ρύθμιση του mail server (από την κονσόλα του Portainer)

1. Portainer → **Containers** → **stalwart** → **Console** → Command: `/bin/sh` → **Connect**.
2. Επικόλλησε **όλο** το παρακάτω και πάτα Enter. **Δεν** αλλάζεις τίποτα μέσα, γιατί παίρνει μόνο του τα στοιχεία από το βήμα 4:

```sh
U="${STALWART_RECOVERY_ADMIN%%:*}"; PW="${STALWART_RECOVERY_ADMIN#*:}"
DOMAIN="${STALWART_HOSTNAME#*.}"; H='Host: localhost:8080'
ACC=$(curl -s -u "$U:$PW" -H "$H" http://127.0.0.1:8080/jmap/session | sed -n 's/.*"urn:stalwart:jmap":"\([^"]*\)".*/\1/p')
echo "hostname: $STALWART_HOSTNAME  domain: $DOMAIN  account: [$ACC]"
curl -s -u "$U:$PW" -H "$H" -H 'Content-Type: application/json' http://127.0.0.1:8080/jmap/ -d '{"using":["urn:ietf:params:jmap:core","urn:stalwart:jmap"],"methodCalls":[["x:Bootstrap/set",{"accountId":"'"$ACC"'","update":{"singleton":{"defaultHostname":"'"$STALWART_HOSTNAME"'","defaultDomain":"'"$DOMAIN"'","requestTlsCertificate":false,"generateDkimKeys":true,"tracer":{"@type":"Stdout","buffered":false,"level":"info","ansi":false,"multiline":false,"enable":true,"lossy":false,"events":{},"eventsPolicy":"exclude"}}}},"0"]]}'; echo
```

3. Θα δεις κάτι σαν:
   ```
   hostname: mail.example.gr  domain: example.gr  account: [d333333]
   {..."updated":{"singleton":{"username":"admin@example.gr","secret":"WOL8feYdq7879dGy"}}...}
   ```
   **Το `username` και το `secret` είναι ο μόνιμος διαχειριστής. Αποθήκευσέ τα ΤΩΡΑ στο password manager.**
   - Αν βγει `account: []`, ο κωδικός στο `STALWART_RECOVERY_ADMIN` είναι λάθος.
4. Portainer → Containers → stalwart → **Restart**.
5. Περίμενε 15 δευτερόλεπτα και άνοιξε τα **Logs**. Πρέπει να δεις γραμμές με `smtp`, `submissions`, `imaps`, `https`. Αυτό σημαίνει ότι ο server είναι έτοιμος.

---

## Βήμα 6: Πρώτη είσοδος στο διαχειριστικό

Άνοιξε **`https://mail.example.gr/admin`** και μπες με το `admin@example.gr` και το `secret` του βήματος 5.

Κάνε αμέσως αυτές τις τρεις ρυθμίσεις. Τα ονόματα των μενού μπορεί να διαφέρουν λίγο.

1. **Settings → HTTP:**
   - *Client IP source* = `X-Forwarded-For`
   - *Forwarded hops* = `1`

   Χωρίς αυτό, μετά από μερικά λάθος logins ο server κλειδώνει τον εαυτό του και δεν μπαίνει κανείς.
2. **Security → Allowed IPs:** πρόσθεσε `10.253.53.0/28`, ή ό,τι έβαλες στο `MAILNET_SUBNET`. Αλλιώς, αν ένας χρήστης βάλει λάθος κωδικό στο webmail, μπορεί να κλειδώσει το webmail για όλους.
3. **Ο λογαριασμός σου → 2FA:** ενεργοποίησε κωδικό από εφαρμογή (Google Authenticator, Authy κ.λπ.).

---

## Βήμα 7: Πιστοποιητικό για τα προγράμματα email

Χωρίς αυτό, το Outlook, το Thunderbird και τα κινητά θα βγάζουν προειδοποίηση για «μη ασφαλή σύνδεση».

1. **Cloudflare** → εικονίδιο προφίλ → **My Profile → API Tokens → Create Token** → template **Edit zone DNS**.
   - Zone Resources: **Include → Specific zone → example.gr**.
   - **Create** και αντέγραψε το token. Εμφανίζεται μία φορά.
2. **Στο admin του mail server:**
   - Πρόσθεσε **DNS server** τύπου **Cloudflare** και βάλε το token.
   - Πρόσθεσε **ACME provider**: Let's Encrypt, challenge **DNS-01**, για το `mail.example.gr`.
3. Σε λίγα λεπτά, στα Logs του stalwart πρέπει να δεις ότι εκδόθηκε πιστοποιητικό.

---

## Βήμα 8: Τα υπόλοιπα DNS records (SPF, DKIM, DMARC κ.λπ.)

Ο server έχει φτιάξει μόνος του τα records που χρειάζονται, μαζί με τα κλειδιά DKIM. Για να τα δεις:

1. Portainer → Containers → stalwart → **Console** → `/bin/sh` → **Connect**.
2. Επικόλλησε, βάζοντας στην πρώτη γραμμή το `secret` του βήματος 5:

```sh
PW='ΤΟ-SECRET-ΤΟΥ-ΒΗΜΑΤΟΣ-5'
DOMAIN="${STALWART_HOSTNAME#*.}"; U="admin@$DOMAIN"; H="Host: $STALWART_HOSTNAME"
ACC=$(curl -s -u "$U:$PW" -H "$H" http://127.0.0.1:8080/jmap/session | sed -n 's/.*"urn:stalwart:jmap":"\([^"]*\)".*/\1/p')
echo "account: [$ACC]"
curl -s -u "$U:$PW" -H "$H" -H 'Content-Type: application/json' http://127.0.0.1:8080/jmap/ -d '{"using":["urn:ietf:params:jmap:core","urn:stalwart:jmap"],"methodCalls":[["x:Domain/get",{"accountId":"'"$ACC"'","ids":null,"properties":["dnsZoneFile"]},"0"]]}' | sed 's/.*"dnsZoneFile":"//; s/","id".*//; s/\\n/\n/g; s/\\"/"/g'
```

Αν έχεις ήδη ενεργοποιήσει 2FA, το `secret` μόνο του δεν αρκεί. Φτιάξε ένα **App password** στο `https://mail.example.gr/account` και βάλ' το στη θέση του.

3. Πέρασε στο **Cloudflare** ό,τι τυπώθηκε, πάντα με **γκρι σύννεφο**. Κάθε γραμμή έχει τη μορφή `ΟΝΟΜΑ.example.gr. IN ΤΥΠΟΣ ΤΙΜΗ`:
   - **Name:** ό,τι είναι πριν από το `.example.gr.`, π.χ. `_dmarc`, `v1-rsa-20261117._domainkey`. Για το σκέτο `example.gr.` γράφεις `@`.
   - **Content:** η τιμή, **χωρίς τα εισαγωγικά**.
   - **DKIM RSA:** η τιμή είναι σπασμένη σε 2 κομμάτια μέσα σε παρενθέσεις. **Ένωσέ τα σε ένα**, χωρίς εισαγωγικά, χωρίς κενό ανάμεσα.
   - **MX:** Name `@`, Mail server `mail.example.gr`, Priority `10`.
   - **SRV:** Priority `0`, Weight `1`, Port και Target όπως στη γραμμή.
   - **Παράλειψε** το `_pop3s._tcp`.
   - Όσα CNAME έβαλες ήδη στο βήμα 2 υπάρχουν ήδη.
4. **DMARC:** ο server προτείνει `p=reject`. Αν **και άλλο σύστημα** στέλνει email ως `@example.gr` (φόρμα στο site, newsletter), βάλε στην αρχή `p=none`.

---

## Βήμα 9: Λογαριασμοί email

Στο admin → **Accounts → Create**:

- **Name:** π.χ. `info`. **Email:** `info@example.gr`. **Password:** δυνατός, από password manager.
- **Quotas:** συμπλήρωσε **μόνο το Disk quota**, π.χ. 5 GB, και άφησε τα υπόλοιπα κενά.
- Φτιάξε και τα `postmaster@`, `abuse@`, `dmarc@` ως **aliases** σε κάποιον λογαριασμό που διαβάζεις.

---

## Βήμα 10: Τελικά

1. **Κωδικός ανάκτησης:** Portainer → Stack `mail` → **Editor** → άλλαξε το `STALWART_RECOVERY_ADMIN` σε **νέο** τυχαίο κωδικό (ή άδειασέ το) → **Update the stack**.
2. **Webmail:** άνοιξε `https://webmail.example.gr` και μπες με `info@example.gr` και τον κωδικό του.
3. **Δοκιμή αποστολής**, μόνο αφού η Hetzner ανοίξει τη θύρα 25 (βήμα 1):
   - Στείλε ένα email σε ένα Gmail → άνοιξέ το → ⋮ → **Show original**. Πρέπει να γράφει **SPF: PASS, DKIM: PASS, DMARC: PASS**.
   - Στείλε ένα email στη διεύθυνση που σου δίνει το https://www.mail-tester.com, με στόχο **10/10**.
4. **Ρυθμίσεις για Outlook, Thunderbird ή κινητό:**

   | | Server | Θύρα | Ασφάλεια |
   |---|---|---|---|
   | Εισερχόμενα (IMAP) | `mail.example.gr` | 993 | SSL/TLS |
   | Εξερχόμενα (SMTP) | `mail.example.gr` | 465 | SSL/TLS |
   | Όνομα χρήστη | ολόκληρο το email | | |

5. **Τις πρώτες 2-4 εβδομάδες στέλνε λίγα email,** κυρίως σε ανθρώπους που απαντούν. Το domain και η IP «χτίζουν φήμη». Μη στέλνεις μαζικά newsletter από εδώ.
6. **Backup:** βλ. [PORTAINER.md](PORTAINER.md) → «Image εργαλείων». Χρειάζεται SSH στον server για το cron.

---

## Αν κάτι δεν δουλεύει

| Τι βλέπεις | Τι σημαίνει / τι κάνεις |
|---|---|
| **"Client metadata documents are disabled"** στο login | Δεν έχει γίνει το βήμα 5 ή το **Restart** μετά από αυτό |
| `account: []` στην κονσόλα | Λάθος κωδικός. Στο βήμα 5 είναι ο κωδικός από το `STALWART_RECOVERY_ADMIN`, στο βήμα 8 το `secret` ή App password |
| `401 Unauthorized` στην κονσόλα | Το ίδιο με το προηγούμενο, ή έχεις 2FA (χρησιμοποίησε App password) |
| Τα **Logs** του stalwart είναι άδεια | Στο βήμα 5 δεν πέρασε η ρύθμιση των logs. Ξαναδές την έξοδο της εντολής |
| `port is already allocated` | Η θύρα είναι πιασμένη από άλλο service. Βάλε `ADMIN_LOCAL_PORT` (βήμα 4) |
| `Pool overlaps` | Βάλε άλλο `MAILNET_SUBNET` (βήμα 4) και ενημέρωσε τα Allowed IPs (βήμα 6) |
| **Λαμβάνει αλλά δεν στέλνει** | Η Hetzner δεν έχει ανοίξει ακόμα τη θύρα 25 (βήμα 1). Έλεγχος από την κονσόλα του stalwart: `curl -sv --max-time 10 telnet://gmail-smtp-in.l.google.com:25 2>&1 \| grep -E "Connected\|timed out"`. Το `timed out` σημαίνει ότι είναι ακόμα μπλοκαρισμένη |
| Τα email πάνε στα **spam** | Έλεγξε τα βήματα 3 και 8, και κάνε το test του mail-tester |
| Προειδοποίηση πιστοποιητικού στο Outlook/κινητό | Δεν έχει γίνει ακόμα το βήμα 7, ή δεν έχει εκδοθεί ακόμα το πιστοποιητικό |
