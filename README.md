[Français](#serveur-de-messagerie-complet--sogo--dovecot--postfix) | [English](#complete-mail-server--sogo--dovecot--postfix)

---

<div align="center">

# 📧 Serveur Mail Complet
### SOGo + Dovecot + Postfix sur Debian 13

[![Debian](https://img.shields.io/badge/Debian-13%20Trixie-red?style=flat-square&logo=debian)](https://www.debian.org/)
[![SOGo](https://img.shields.io/badge/SOGo-Groupware-blue?style=flat-square)](https://www.sogo.nu/)
[![Postfix](https://img.shields.io/badge/Postfix-SMTP-orange?style=flat-square)](http://www.postfix.org/)
[![Dovecot](https://img.shields.io/badge/Dovecot-IMAP-green?style=flat-square)](https://www.dovecot.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](https://opensource.org/licenses/MIT)
[![Author](https://img.shields.io/badge/Author-Di--Enilson%20Etienne-purple?style=flat-square)](https://github.com/di-enilson-etienne)

</div>

---

# Serveur de messagerie complet — SOGo + Dovecot + Postfix

Script d'installation et de configuration automatique d'un serveur de messagerie complet sur **Debian 13 (Trixie)**. Ce script installe et configure SOGo (webmail), Dovecot (IMAP), Postfix (SMTP), Apache2 (proxy), MariaDB et Memcached.

**Fonctionnalités :**

- Installation entièrement automatisée avec menu interactif
- Saisie interactive de tous les paramètres (domaine, base de données, mot de passe, etc.)
- Gestion complète des utilisateurs (ajout, suppression, changement de mot de passe)
- Tests SMTP et IMAP intégrés
- Compatible avec Outlook, Thunderbird et tout client IMAP/SMTP
- Résolution automatique des erreurs courantes de Dovecot 2.4 et Postfix

---

## Architecture

```
Client (Navigateur / Outlook / Thunderbird)
        │
        ▼
   Apache2 :80  ──────────────────────▶  SOGo :20000
        │                                     │
        │                              ┌──────┴──────┐
        │                              │             │
        ▼                              ▼             ▼
   Dovecot :143                  Postfix :25    MariaDB :3306
   (IMAP — lecture)              (SMTP — envoi)  (Base de données)
        │                              │
        └──────────────┬───────────────┘
                       ▼
              /var/mail/<user>@<domain>/
              (Stockage Maildir)
```

---

## Prérequis

- Debian 13 (Trixie) — serveur minimal
- Accès **root**
- Connexion internet
- Adresse IP fixe recommandée

---

## Installation rapide

```bash
# Télécharger le script
wget -O install_mail_server.sh https://raw.githubusercontent.com/di-enilson-etienne/sogo-mail-server/main/install_mail_server.sh

# Rendre exécutable
chmod +x install_mail_server.sh

# Lancer en root
sudo bash install_mail_server.sh
```

> **Note :** Le script doit être exécuté en root (`sudo` ou directement en root).

---

## Installation étape par étape

### Étape 1 — Saisie des paramètres

Le script vous demandera :

| Paramètre | Exemple |
|-----------|---------|
| Nom de domaine | `entreprise.local` |
| Hostname du serveur | `mail` |
| Nom de la base de données | `sogo` |
| Utilisateur MySQL | `sogo` |
| Mot de passe MySQL | `MotDePasseFort` |
| Mot de passe administrateur | `admin123` |

### Étape 2 — Installation des dépendances

Le script installe automatiquement :

```bash
apt install -y mariadb-server mariadb-client memcached \
    postfix postfix-mysql postfix-lmdb \
    dovecot-core dovecot-imapd dovecot-mysql dovecot-sieve \
    apache2 sogo sogo-activesync mailutils
```

### Étape 3 — Configuration de MariaDB

Création automatique de la base de données et des tables SOGo :

```sql
CREATE DATABASE sogo CHARACTER SET utf8mb4;
CREATE USER 'sogo'@'localhost' IDENTIFIED BY 'MotDePasseFort';
GRANT ALL PRIVILEGES ON sogo.* TO 'sogo'@'localhost';
```

Tables créées : `sogo_view`, `sogo_user_profile`, `sogo_folder_info`, `sogo_sessions_folder`, `sogo_store`, `sogo_acl`, `sogo_cache_folder`

> ⚠️ **Important :** La colonne `c_name` dans `sogo_user_profile` doit avoir `DEFAULT ''` sinon SOGo génère une erreur MySQL à la première connexion.

### Étape 4 — Configuration de Dovecot

> ⚠️ **Dovecot 2.4 (Debian 13) utilise une syntaxe différente de Dovecot 2.3 !**

| Ancienne syntaxe (❌) | Nouvelle syntaxe (✅) |
|----------------------|----------------------|
| `disable_plaintext_auth = no` | Supprimé |
| `passdb { driver = pam }` | `passdb pam { }` |
| `userdb { driver = passwd }` | `userdb passwd { }` |
| `passdb { driver = sql\n  args = fichier }` | `passdb sql { passdb_sql_query = ... }` |

Configuration retenue (`/etc/dovecot/conf.d/10-auth.conf`) :

```ini
auth_mechanisms = plain login

passdb passwd-file {
  passwd_file_path = /etc/dovecot/users
  default_password_scheme = PLAIN
}

userdb static {
  fields {
    uid = vmail
    gid = vmail
    home = /var/mail/%{user}
    mail_driver = maildir
    mail_path = /var/mail/%{user}
  }
}
```

Fichier `/etc/dovecot/users` :
```
user@domaine.local:motdepasse
admin@domaine.local:motdepasse
```

> ⚠️ **Permissions :** Le fichier `/etc/dovecot/users` doit être en mode **644** (pas 600). Avec 600, l'utilisateur `dovecot` ne peut pas le lire → erreur `Permission denied`.

### Étape 5 — Configuration de Postfix

> ⚠️ **Erreur fréquente :** Ne jamais mettre le domaine dans `mydestination` ET `virtual_mailbox_domains` en même temps.

```bash
# MAUVAIS — provoque un conflit
mydestination = $myhostname, localhost, $mydomain
virtual_mailbox_domains = entreprise.local   # CONFLIT !

# CORRECT
mydestination = $myhostname, localhost.$mydomain, localhost
virtual_mailbox_domains = entreprise.local
```

Configuration complète appliquée :

```bash
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
postconf -e "virtual_mailbox_base = /var/mail"
postconf -e "virtual_mailbox_domains = entreprise.local"
postconf -e "virtual_mailbox_maps = lmdb:/etc/postfix/vmailbox"
postconf -e "virtual_uid_maps = static:5000"
postconf -e "virtual_gid_maps = static:5000"
postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
postconf -e "compatibility_level = 3.11"
```

Fichier `/etc/postfix/vmailbox` :
```
user@domaine.local    user@domaine.local/
admin@domaine.local   admin@domaine.local/
```

Compiler la table :
```bash
postmap lmdb:/etc/postfix/vmailbox
postfix reload
```

### Étape 6 — Configuration de SOGo

```ini
# /etc/sogo/sogo.conf
{
  SOGoIMAPServer = "127.0.0.1";      # IPv4 obligatoire (pas localhost)
  SOGoSMTPServer = "127.0.0.1";      # IPv4 obligatoire (pas localhost)
  SOGoMailingMechanism = "smtp";
  SOGoMailDomain = "entreprise.local";
  WOPort = 127.0.0.1:20000;
  WOWorkersCount = 3;
}
```

> ⚠️ Utiliser `127.0.0.1` et non `localhost`. SOGo se connecte en IPv6 (::1) avec `localhost`, mais Postfix/Dovecot n'écoutent que sur IPv4.

### Étape 7 — Configuration Apache

```bash
a2enmod proxy proxy_http alias headers
```

```apache
<VirtualHost *:80>
    Alias /SOGo.woa/WebServerResources /usr/share/GNUstep/SOGo/WebServerResources
    <Directory /usr/share/GNUstep/SOGo/WebServerResources>
        Require all granted
        Options FollowSymLinks
    </Directory>
    ProxyPreserveHost On
    ProxyPass /SOGo.woa/WebServerResources !
    ProxyPass /SOGo http://127.0.0.1:20000/SOGo
    ProxyPassReverse /SOGo http://127.0.0.1:20000/SOGo
</VirtualHost>
```

---

## Menu du script

```
── Installation ──────────────────────────────────
  1.  Installation complète automatique (recommandée)
  2.  Saisir les paramètres uniquement
  3.  Installer les dépendances
  4.  Configurer la base de données
  5.  Configurer Dovecot (IMAP)
  6.  Configurer Postfix (SMTP)
  7.  Configurer SOGo
  8.  Configurer Apache

── Utilisateurs ──────────────────────────────────
  9.  Ajouter un utilisateur
  10. Lister les utilisateurs
  11. Supprimer un utilisateur
  12. Changer le mot de passe

── Maintenance ───────────────────────────────────
  13. Statut des services
  14. Tester SMTP (envoi email)
  15. Tester IMAP (auth Dovecot)
  16. Voir les logs
  17. Redémarrer tous les services
  18. Corriger les permissions
  19. Informations de connexion
```

---

## Gestion des utilisateurs

### Ajouter un utilisateur

```bash
sudo addmailuser <prenom> "<Nom Complet>" <motdepasse>

# Exemple
sudo addmailuser marie "Marie Dupont" marie123
```

Le script effectue automatiquement :
1. Ajout dans `/etc/dovecot/users`
2. Création du dossier `/var/mail/marie@domaine.local/{cur,new,tmp}`
3. Ajout dans `/etc/postfix/vmailbox` + recompilation
4. Ajout dans la base MySQL (SOGo)
5. Redémarrage de Dovecot

### Supprimer un utilisateur

Utiliser le menu → Option 11

---

## Accès depuis les clients

### Webmail SOGo

```
http://<IP_SERVEUR>/SOGo
```

> Ajouter le domaine dans `/etc/hosts` des clients si nécessaire :
> ```
> 192.168.1.10  entreprise.local
> ```

### Outlook / Thunderbird

| Paramètre | Valeur |
|-----------|--------|
| **Serveur IMAP** | `192.168.1.10` |
| **Port IMAP** | `143` |
| **Chiffrement IMAP** | Aucun |
| **Serveur SMTP** | `192.168.1.10` |
| **Port SMTP** | `25` |
| **Chiffrement SMTP** | Aucun |
| **Login** | `user@entreprise.local` |
| **Mot de passe** | Votre mot de passe |

---

## Erreurs fréquentes et solutions

| Erreur | Cause | Solution |
|--------|-------|----------|
| `No passdbs specified` | Fichier 10-auth.conf manquant | Créer `/etc/dovecot/conf.d/10-auth.conf` |
| `disable_plaintext_auth: Unknown setting` | Paramètre supprimé dans Dovecot 2.4 | Retirer ce paramètre |
| `Permission denied on /etc/dovecot/users` | Mode 600 — dovecot ne peut lire | `chmod 644 /etc/dovecot/users` |
| `user unknown` (PAM) | PAM reçoit `user@domain` au lieu de `user` | Utiliser passwd-file à la place de PAM |
| `Could not connect to SMTP server` | SOGo utilise IPv6 via `localhost` | Mettre `127.0.0.1` dans sogo.conf |
| `require state 2, now in 1` | Postfix refuse les connexions | Configurer `smtpd_relay_restrictions` |
| `domain in BOTH mydestination and virtual_mailbox_domains` | Conflit Postfix | Retirer `$mydomain` de `mydestination` |
| `User unknown in virtual mailbox table` | Utilisateur absent de vmailbox | Ajouter dans vmailbox + `postmap` |
| `Field c_name doesn't have default value` | Table MySQL mal créée | `ALTER TABLE sogo_user_profile MODIFY c_name VARCHAR(255) DEFAULT ''` |
| `Temporary lookup failure` | DNS ne résout pas le domaine local | Ajouter dans `/etc/hosts` du serveur |
| `open database vmailbox.db: No such file or directory` | hash/btree déprécié dans Postfix 3.11 | Utiliser `lmdb` + `apt install postfix-lmdb` |

---

## Commandes utiles

```bash
# Statut de tous les services
systemctl status sogo dovecot postfix apache2 mariadb

# Logs en temps réel
journalctl -fu dovecot
journalctl -fu postfix
tail -f /var/log/sogo/sogo.log

# Tester l'authentification IMAP
doveadm auth test user@domaine.local motdepasse

# Vérifier les ports ouverts
ss -tlnp | grep -E "25|143|80|20000"

# File d'attente mail
mailq

# Tester la config Dovecot
doveconf -n

# Tester la config Postfix
postconf -n
```

---

## Permissions importantes

| Fichier/Dossier | Mode | Propriétaire |
|-----------------|------|--------------|
| `/etc/dovecot/users` | `644` | `root:root` |
| `/etc/sogo/sogo.conf` | `640` | `root:sogo` |
| `/var/mail/<user>/` | `770` | `vmail:vmail` |
| `/var/log/sogo/` | `755` | `sogo:sogo` |
| `/run/sogo/` | `755` | `sogo:sogo` |

---

## Crédits

Créé par **Di-Enilson Etienne**

Basé sur l'expérience pratique d'installation sur Debian 13 et la résolution des erreurs rencontrées avec Dovecot 2.4 et Postfix 3.11.

---
---

<div align="center">

# 📧 Complete Mail Server
### SOGo + Dovecot + Postfix on Debian 13

[![Debian](https://img.shields.io/badge/Debian-13%20Trixie-red?style=flat-square&logo=debian)](https://www.debian.org/)
[![SOGo](https://img.shields.io/badge/SOGo-Groupware-blue?style=flat-square)](https://www.sogo.nu/)
[![Postfix](https://img.shields.io/badge/Postfix-SMTP-orange?style=flat-square)](http://www.postfix.org/)
[![Dovecot](https://img.shields.io/badge/Dovecot-IMAP-green?style=flat-square)](https://www.dovecot.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](https://opensource.org/licenses/MIT)
[![Author](https://img.shields.io/badge/Author-Di--Enilson%20Etienne-purple?style=flat-square)](https://github.com/di-enilson-etienne)

</div>

---

# Complete Mail Server — SOGo + Dovecot + Postfix

Automated installation and configuration script for a complete mail server on **Debian 13 (Trixie)**. This script installs and configures SOGo (webmail), Dovecot (IMAP), Postfix (SMTP), Apache2 (reverse proxy), MariaDB and Memcached.

**Features:**

- Fully automated installation with interactive menu
- Interactive input for all parameters (domain, database, passwords, etc.)
- Complete user management (add, delete, change password)
- Built-in SMTP and IMAP tests
- Compatible with Outlook, Thunderbird and any IMAP/SMTP client
- Automatic resolution of common Dovecot 2.4 and Postfix errors

---

## Architecture

```
Client (Browser / Outlook / Thunderbird)
        │
        ▼
   Apache2 :80  ──────────────────────▶  SOGo :20000
        │                                     │
        │                              ┌──────┴──────┐
        │                              │             │
        ▼                              ▼             ▼
   Dovecot :143                  Postfix :25    MariaDB :3306
   (IMAP — reading)              (SMTP — sending) (Database)
        │                              │
        └──────────────┬───────────────┘
                       ▼
              /var/mail/<user>@<domain>/
              (Maildir Storage)
```

---

## Requirements

- Debian 13 (Trixie) — minimal server installation
- **Root** access
- Internet connection
- Fixed IP address recommended

---

## Quick Install

```bash
# Download the script
wget -O install_mail_server.sh https://raw.githubusercontent.com/di-enilson-etienne/sogo-mail-server/main/install_mail_server.sh

# Make it executable
chmod +x install_mail_server.sh

# Run as root
sudo bash install_mail_server.sh
```

> **Note:** The script must be run as root (`sudo` or directly as root).

---

## Step-by-Step Installation

### Step 1 — Parameter Input

The script will ask for:

| Parameter | Example |
|-----------|---------|
| Domain name | `company.local` |
| Mail server hostname | `mail` |
| Database name | `sogo` |
| MySQL user | `sogo` |
| MySQL password | `StrongPassword` |
| Admin password | `admin123` |

### Step 2 — Installing Dependencies

The script automatically installs:

```bash
apt install -y mariadb-server mariadb-client memcached \
    postfix postfix-mysql postfix-lmdb \
    dovecot-core dovecot-imapd dovecot-mysql dovecot-sieve \
    apache2 sogo sogo-activesync mailutils
```

### Step 3 — MariaDB Configuration

Automatic creation of the SOGo database and tables:

```sql
CREATE DATABASE sogo CHARACTER SET utf8mb4;
CREATE USER 'sogo'@'localhost' IDENTIFIED BY 'StrongPassword';
GRANT ALL PRIVILEGES ON sogo.* TO 'sogo'@'localhost';
```

Tables created: `sogo_view`, `sogo_user_profile`, `sogo_folder_info`, `sogo_sessions_folder`, `sogo_store`, `sogo_acl`, `sogo_cache_folder`

> ⚠️ **Important:** The `c_name` column in `sogo_user_profile` must have `DEFAULT ''` — otherwise SOGo throws a MySQL error on first login.

### Step 4 — Dovecot Configuration

> ⚠️ **Dovecot 2.4 (Debian 13) uses a completely different syntax from Dovecot 2.3!**

| Old syntax (❌) | New syntax (✅) |
|----------------|----------------|
| `disable_plaintext_auth = no` | Removed |
| `passdb { driver = pam }` | `passdb pam { }` |
| `userdb { driver = passwd }` | `userdb passwd { }` |
| `passdb { driver = sql\n  args = file }` | `passdb sql { passdb_sql_query = ... }` |

Configuration used (`/etc/dovecot/conf.d/10-auth.conf`):

```ini
auth_mechanisms = plain login

passdb passwd-file {
  passwd_file_path = /etc/dovecot/users
  default_password_scheme = PLAIN
}

userdb static {
  fields {
    uid = vmail
    gid = vmail
    home = /var/mail/%{user}
    mail_driver = maildir
    mail_path = /var/mail/%{user}
  }
}
```

File `/etc/dovecot/users`:
```
user@company.local:password
admin@company.local:password
```

> ⚠️ **Permissions:** `/etc/dovecot/users` must be mode **644** (not 600). With 600, the `dovecot` user cannot read it → `Permission denied` error.

### Step 5 — Postfix Configuration

> ⚠️ **Common error:** Never list the domain in both `mydestination` AND `virtual_mailbox_domains`.

```bash
# WRONG — causes a conflict
mydestination = $myhostname, localhost, $mydomain
virtual_mailbox_domains = company.local   # CONFLICT!

# CORRECT
mydestination = $myhostname, localhost.$mydomain, localhost
virtual_mailbox_domains = company.local
```

Full configuration applied:

```bash
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
postconf -e "virtual_mailbox_base = /var/mail"
postconf -e "virtual_mailbox_domains = company.local"
postconf -e "virtual_mailbox_maps = lmdb:/etc/postfix/vmailbox"
postconf -e "virtual_uid_maps = static:5000"
postconf -e "virtual_gid_maps = static:5000"
postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
postconf -e "compatibility_level = 3.11"
```

File `/etc/postfix/vmailbox`:
```
user@company.local    user@company.local/
admin@company.local   admin@company.local/
```

Compile the table:
```bash
postmap lmdb:/etc/postfix/vmailbox
postfix reload
```

### Step 6 — SOGo Configuration

```ini
# /etc/sogo/sogo.conf
{
  SOGoIMAPServer = "127.0.0.1";      # Must be IPv4 (not localhost)
  SOGoSMTPServer = "127.0.0.1";      # Must be IPv4 (not localhost)
  SOGoMailingMechanism = "smtp";
  SOGoMailDomain = "company.local";
  WOPort = 127.0.0.1:20000;
  WOWorkersCount = 3;
}
```

> ⚠️ Use `127.0.0.1` not `localhost`. SOGo connects via IPv6 (::1) when using `localhost`, but Postfix/Dovecot only listen on IPv4.

### Step 7 — Apache Configuration

```bash
a2enmod proxy proxy_http alias headers
```

```apache
<VirtualHost *:80>
    Alias /SOGo.woa/WebServerResources /usr/share/GNUstep/SOGo/WebServerResources
    <Directory /usr/share/GNUstep/SOGo/WebServerResources>
        Require all granted
        Options FollowSymLinks
    </Directory>
    ProxyPreserveHost On
    ProxyPass /SOGo.woa/WebServerResources !
    ProxyPass /SOGo http://127.0.0.1:20000/SOGo
    ProxyPassReverse /SOGo http://127.0.0.1:20000/SOGo
</VirtualHost>
```

---

## Script Menu

```
── Installation ──────────────────────────────────
  1.  Full automatic installation (recommended)
  2.  Enter parameters only
  3.  Install dependencies
  4.  Configure database
  5.  Configure Dovecot (IMAP)
  6.  Configure Postfix (SMTP)
  7.  Configure SOGo
  8.  Configure Apache

── Users ─────────────────────────────────────────
  9.  Add a user
  10. List users
  11. Delete a user
  12. Change password

── Maintenance ───────────────────────────────────
  13. Service status
  14. Test SMTP (send email)
  15. Test IMAP (Dovecot auth)
  16. View logs
  17. Restart all services
  18. Fix permissions
  19. Connection information
```

---

## User Management

### Add a user

```bash
sudo addmailuser <username> "<Full Name>" <password>

# Example
sudo addmailuser marie "Marie Dupont" marie123
```

The script automatically:
1. Adds to `/etc/dovecot/users`
2. Creates `/var/mail/marie@domain.local/{cur,new,tmp}`
3. Adds to `/etc/postfix/vmailbox` + recompiles
4. Adds to MySQL database (SOGo)
5. Restarts Dovecot

### Delete a user

Use menu → Option 11

---

## Client Access

### SOGo Webmail

```
http://<SERVER_IP>/SOGo
```

> Add domain to `/etc/hosts` on client machines if needed:
> ```
> 192.168.1.10  company.local
> ```

### Outlook / Thunderbird

| Parameter | Value |
|-----------|-------|
| **IMAP Server** | `192.168.1.10` |
| **IMAP Port** | `143` |
| **IMAP Encryption** | None |
| **SMTP Server** | `192.168.1.10` |
| **SMTP Port** | `25` |
| **SMTP Encryption** | None |
| **Username** | `user@company.local` |
| **Password** | Your password |

---

## Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `No passdbs specified` | Missing 10-auth.conf | Create `/etc/dovecot/conf.d/10-auth.conf` |
| `disable_plaintext_auth: Unknown setting` | Setting removed in Dovecot 2.4 | Remove this parameter |
| `Permission denied on /etc/dovecot/users` | Mode 600 — dovecot cannot read | `chmod 644 /etc/dovecot/users` |
| `user unknown` (PAM) | PAM receives `user@domain` instead of `user` | Use passwd-file instead of PAM |
| `Could not connect to SMTP server` | SOGo uses IPv6 via `localhost` | Set `127.0.0.1` in sogo.conf |
| `require state 2, now in 1` | Postfix rejecting connections | Configure `smtpd_relay_restrictions` |
| `domain in BOTH mydestination and virtual_mailbox_domains` | Postfix conflict | Remove `$mydomain` from `mydestination` |
| `User unknown in virtual mailbox table` | User missing from vmailbox | Add to vmailbox + run `postmap` |
| `Field c_name doesn't have default value` | MySQL table incorrectly created | `ALTER TABLE sogo_user_profile MODIFY c_name VARCHAR(255) DEFAULT ''` |
| `Temporary lookup failure` | DNS cannot resolve local domain | Add to `/etc/hosts` on the server |
| `open database vmailbox.db: No such file or directory` | hash/btree deprecated in Postfix 3.11 | Use `lmdb` + `apt install postfix-lmdb` |

---

## Useful Commands

```bash
# Status of all services
systemctl status sogo dovecot postfix apache2 mariadb

# Real-time logs
journalctl -fu dovecot
journalctl -fu postfix
tail -f /var/log/sogo/sogo.log

# Test IMAP authentication
doveadm auth test user@company.local password

# Check open ports
ss -tlnp | grep -E "25|143|80|20000"

# Mail queue
mailq

# Test Dovecot config
doveconf -n

# Test Postfix config
postconf -n
```

---

## Important Permissions

| File/Directory | Mode | Owner |
|----------------|------|-------|
| `/etc/dovecot/users` | `644` | `root:root` |
| `/etc/sogo/sogo.conf` | `640` | `root:sogo` |
| `/var/mail/<user>/` | `770` | `vmail:vmail` |
| `/var/log/sogo/` | `755` | `sogo:sogo` |
| `/run/sogo/` | `755` | `sogo:sogo` |

---

## Credits

Created by **Di-Enilson Etienne**

Based on practical installation experience on Debian 13 and resolution of errors encountered with Dovecot 2.4 and Postfix 3.11.

---

<div align="center">
<sub>MIT License — Di-Enilson Etienne — 2026</sub>
</div>
