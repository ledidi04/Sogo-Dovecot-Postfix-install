#!/bin/bash
# ============================================================
# Script d'installation complète : SOGo + Dovecot + Postfix
# Debian 13 (Trixie) - Serveur de messagerie complet
# Auteur : Di-Enilson Etienne
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# VARIABLES GLOBALES (saisies par l'utilisateur)
# ============================================================
DOMAIN=""
HOSTNAME_MAIL=""
DB_NAME=""
DB_USER=""
DB_PASS=""
ADMIN_EMAIL=""
ADMIN_PASS=""

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================

show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     INSTALLATION SERVEUR MAIL : SOGo + Dovecot + Postfix    ║${NC}"
    echo -e "${BLUE}║                    Debian 13 (Trixie)                       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERREUR] Ce script doit être exécuté en root !${NC}"
        echo "Utilisez : sudo bash $0"
        exit 1
    fi
}

log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ATTENTION]${NC} $1"; }
log_err()  { echo -e "${RED}[ERREUR]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

pause() {
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
}

# ============================================================
# ÉTAPE 0 : SAISIE DES PARAMÈTRES
# ============================================================
collect_params() {
    show_header
    echo -e "${GREEN}=== CONFIGURATION INITIALE ===${NC}"
    echo -e "${YELLOW}Veuillez renseigner les informations suivantes :${NC}"
    echo ""

    # Domaine
    while [ -z "$DOMAIN" ]; do
        read -p "Nom de domaine (ex: entreprise.local) : " DOMAIN
    done

    # Hostname mail
    while [ -z "$HOSTNAME_MAIL" ]; do
        read -p "Hostname du serveur mail (ex: mail) : " HOSTNAME_MAIL
    done
    FQDN="${HOSTNAME_MAIL}.${DOMAIN}"

    # Base de données
    while [ -z "$DB_NAME" ]; do
        read -p "Nom de la base de données SOGo (ex: sogo) : " DB_NAME
    done

    while [ -z "$DB_USER" ]; do
        read -p "Utilisateur MySQL pour SOGo (ex: sogo) : " DB_USER
    done

    while [ -z "$DB_PASS" ]; do
        read -sp "Mot de passe MySQL pour SOGo : " DB_PASS
        echo ""
    done

    # Admin SOGo
    ADMIN_EMAIL="admin@${DOMAIN}"
    while [ -z "$ADMIN_PASS" ]; do
        read -sp "Mot de passe administrateur SOGo (${ADMIN_EMAIL}) : " ADMIN_PASS
        echo ""
    done

    echo ""
    echo -e "${CYAN}=== RÉCAPITULATIF ===${NC}"
    echo "  Domaine        : $DOMAIN"
    echo "  FQDN serveur   : $FQDN"
    echo "  Base de données: $DB_NAME"
    echo "  Utilisateur DB : $DB_USER"
    echo "  Admin SOGo     : $ADMIN_EMAIL"
    echo ""
    read -p "Confirmer ces paramètres ? (oui/non) : " CONFIRM
    if [ "$CONFIRM" != "oui" ]; then
        DOMAIN=""
        DB_NAME=""
        DB_USER=""
        DB_PASS=""
        ADMIN_PASS=""
        collect_params
    fi
}

# ============================================================
# ÉTAPE 1 : MISE À JOUR + DÉPENDANCES
# ============================================================
install_dependencies() {
    show_header
    echo -e "${GREEN}=== ÉTAPE 1 : Installation des dépendances ===${NC}"
    echo ""

    log_info "Mise à jour du système..."
    apt update -qq && apt upgrade -y -qq
    log_ok "Système mis à jour."

    log_info "Installation des outils de base..."
    apt install -y -qq \
        curl wget net-tools telnet \
        mariadb-server mariadb-client \
        memcached \
        postfix postfix-mysql \
        dovecot-core dovecot-imapd dovecot-mysql dovecot-sieve \
        apache2 \
        sogo sogo-activesync \
        mailutils 2>/dev/null

    log_ok "Dépendances installées."

    # Activer les services
    systemctl enable --now mariadb memcached apache2 postfix dovecot sogo 2>/dev/null
    log_ok "Services activés."
    pause
}

# ============================================================
# ÉTAPE 2 : CONFIGURATION MARIADB
# ============================================================
config_database() {
    show_header
    echo -e "${GREEN}=== ÉTAPE 2 : Configuration de la base de données ===${NC}"
    echo ""

    log_info "Sécurisation de MariaDB..."
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null
    mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null

    log_info "Création de la base de données ${DB_NAME}..."
    mysql << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    log_ok "Base de données créée."

    log_info "Création des tables SOGo..."
    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" << EOF
CREATE TABLE IF NOT EXISTS sogo_user_profile (
  c_uid  VARCHAR(255) NOT NULL,
  c_name VARCHAR(255) NOT NULL DEFAULT '',
  c_defaults  MEDIUMTEXT,
  c_settings  TEXT,
  PRIMARY KEY (c_uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sogo_folder_info (
  c_path        VARCHAR(255) NOT NULL,
  c_path1       VARCHAR(255) NOT NULL,
  c_path2       VARCHAR(255),
  c_path3       VARCHAR(255),
  c_path4       VARCHAR(255),
  c_foldername  VARCHAR(255) NOT NULL,
  c_location    VARCHAR(2048),
  c_quick_location VARCHAR(2048),
  c_acl_location   VARCHAR(2048),
  c_type        SMALLINT NOT NULL,
  PRIMARY KEY (c_path)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sogo_sessions_folder (
  c_id          VARCHAR(255) NOT NULL,
  c_value       VARCHAR(4096) NOT NULL,
  c_creationdate INT NOT NULL,
  c_lastseen    INT NOT NULL,
  PRIMARY KEY (c_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sogo_store (
  c_path        VARCHAR(255) NOT NULL,
  c_name        VARCHAR(255) NOT NULL,
  c_content     LONGTEXT,
  c_creationdate INT NOT NULL,
  c_lastmodified INT NOT NULL,
  c_version     INT NOT NULL DEFAULT 0,
  c_deleted     INT NOT NULL DEFAULT 0,
  PRIMARY KEY (c_path, c_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sogo_acl (
  c_path        VARCHAR(255) NOT NULL,
  c_uid         VARCHAR(255) NOT NULL,
  c_rights      VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sogo_cache_folder (
  c_path        VARCHAR(255) NOT NULL,
  c_uid         VARCHAR(255) NOT NULL,
  c_creationdate INT NOT NULL,
  c_lastmodified INT NOT NULL,
  c_version     INT NOT NULL DEFAULT 0,
  c_deleted     INT NOT NULL DEFAULT 0,
  c_content     LONGTEXT,
  PRIMARY KEY (c_path, c_uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sogo_view (
  c_uid         VARCHAR(255) NOT NULL PRIMARY KEY,
  c_name        VARCHAR(255),
  c_password    VARCHAR(512),
  c_cn          VARCHAR(255),
  mail          VARCHAR(255),
  description   VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF

    log_ok "Tables créées."

    log_info "Ajout de l'administrateur..."
    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" << EOF
INSERT INTO sogo_view (c_uid, c_name, c_password, c_cn, mail)
VALUES ('${ADMIN_EMAIL}', 'admin', '${ADMIN_PASS}', 'Administrateur', '${ADMIN_EMAIL}')
ON DUPLICATE KEY UPDATE c_password='${ADMIN_PASS}';
EOF
    log_ok "Administrateur ajouté : ${ADMIN_EMAIL}"
    pause
}

# ============================================================
# ÉTAPE 3 : CONFIGURATION DOVECOT
# ============================================================
config_dovecot() {
    show_header
    echo -e "${GREEN}=== ÉTAPE 3 : Configuration de Dovecot ===${NC}"
    echo ""

    # Créer le groupe et utilisateur vmail si nécessaire
    if ! getent group vmail > /dev/null; then
        groupadd -g 5000 vmail
        log_ok "Groupe vmail créé (gid=5000)."
    fi
    if ! getent passwd vmail > /dev/null; then
        useradd -g vmail -u 5000 -d /var/mail -s /usr/sbin/nologin vmail
        log_ok "Utilisateur vmail créé."
    fi

    # Répertoire mail de base
    mkdir -p /var/mail
    chown vmail:vmail /var/mail
    chmod 770 /var/mail

    # Fichier d'authentification passwd-file
    cat > /etc/dovecot/users << EOF
${ADMIN_EMAIL}:${ADMIN_PASS}
EOF
    chmod 644 /etc/dovecot/users
    log_ok "Fichier /etc/dovecot/users créé."

    # Créer le dossier mail de l'admin
    mkdir -p "/var/mail/${ADMIN_EMAIL}/{cur,new,tmp}"
    chown -R vmail:vmail "/var/mail/${ADMIN_EMAIL}"

    # Configuration principale auth
    cat > /etc/dovecot/conf.d/10-auth.conf << EOF
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
EOF
    log_ok "10-auth.conf configuré."

    # Configuration mail (maildir dans /var/mail)
    sed -i 's|^mail_driver.*||' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null
    sed -i 's|^mail_home.*||' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null
    sed -i 's|^mail_path.*||' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null
    sed -i 's|^mail_inbox_path.*||' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null

    cat >> /etc/dovecot/conf.d/10-mail.conf << EOF

# Configuration maildir
mail_driver = maildir
mail_home = /var/mail/%{user}
mail_path = /var/mail/%{user}
EOF
    log_ok "10-mail.conf configuré."

    # Désactiver SSL (réseau local)
    sed -i 's/^ssl = yes/ssl = no/' /etc/dovecot/conf.d/10-ssl.conf 2>/dev/null
    sed -i 's/^ssl = required/ssl = no/' /etc/dovecot/conf.d/10-ssl.conf 2>/dev/null

    # Redémarrer Dovecot
    systemctl restart dovecot
    sleep 2

    if systemctl is-active --quiet dovecot; then
        log_ok "Dovecot démarré avec succès."
    else
        log_err "Dovecot a échoué. Vérifiez : journalctl -u dovecot"
    fi
    pause
}

# ============================================================
# ÉTAPE 4 : CONFIGURATION POSTFIX
# ============================================================
config_postfix() {
    show_header
    echo -e "${GREEN}=== ÉTAPE 4 : Configuration de Postfix ===${NC}"
    echo ""

    FQDN="${HOSTNAME_MAIL}.${DOMAIN}"

    # Fixer le hostname
    hostnamectl set-hostname "$FQDN" 2>/dev/null

    # Configuration principale postfix
    postconf -e "myhostname = ${FQDN}"
    postconf -e "mydomain = ${DOMAIN}"
    postconf -e "myorigin = \$mydomain"
    postconf -e "inet_interfaces = all"
    postconf -e "inet_protocols = ipv4"

    # IMPORTANT : ne pas mettre le domaine dans mydestination
    # (conflit avec virtual_mailbox_domains)
    postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"

    postconf -e "mynetworks = 127.0.0.0/8, 192.168.0.0/16, 10.0.0.0/8"
    postconf -e "mailbox_size_limit = 0"

    # Virtual mailbox (livraison dans /var/mail/<user>@<domain>/)
    postconf -e "virtual_mailbox_base = /var/mail"
    postconf -e "virtual_mailbox_domains = ${DOMAIN}"
    postconf -e "virtual_mailbox_maps = hash:/etc/postfix/vmailbox"
    postconf -e "virtual_uid_maps = static:5000"
    postconf -e "virtual_gid_maps = static:5000"
    postconf -e "home_mailbox ="

    # Restrictions SMTP (évite l'erreur "no working instance")
    postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
    postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

    # Compatibilité
    postconf -e "compatibility_level = 3.6"

    # Créer la table vmailbox avec l'admin
    cat > /etc/postfix/vmailbox << EOF
${ADMIN_EMAIL}    ${ADMIN_EMAIL}/
EOF
    postmap /etc/postfix/vmailbox
    log_ok "Table vmailbox créée."

    # Redémarrer Postfix
    systemctl restart postfix
    sleep 2

    if systemctl is-active --quiet postfix; then
        log_ok "Postfix démarré avec succès."
    else
        log_err "Postfix a échoué. Vérifiez : journalctl -u postfix"
    fi
    pause
}

# ============================================================
# ÉTAPE 5 : CONFIGURATION SOGo
# ============================================================
config_sogo() {
    show_header
    echo -e "${GREEN}=== ÉTAPE 5 : Configuration de SOGo ===${NC}"
    echo ""

    ENCRYPTION_KEY="SOGoKey$(date +%s)$(openssl rand -hex 8)"

    mkdir -p /var/log/sogo /run/sogo
    chown -R sogo:sogo /var/log/sogo /run/sogo 2>/dev/null

    cat > /etc/sogo/sogo.conf << EOF
{
  SOGoProfileURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_user_profile";
  OCSFolderInfoURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_folder_info";
  OCSSessionsFolderURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_sessions_folder";
  OCSStoreURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_store";
  OCSAclURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_acl";
  OCSCacheFolderURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_cache_folder";

  SOGoIMAPServer = "127.0.0.1";
  SOGoMailingMechanism = "smtp";
  SOGoSMTPServer = "127.0.0.1";

  SOGoMailDomain = "${DOMAIN}";
  SOGoLanguage = "French";
  SOGoTimeZone = "America/Port-au-Prince";
  SOGoFirstDayOfWeek = "1";
  SOGoEncryptionKey = "${ENCRYPTION_KEY}";
  SOGoEnablePublicAccess = YES;
  SOGoPasswordChangeEnabled = NO;

  SOGoMemcachedHost = "127.0.0.1";

  WOPort = 127.0.0.1:20000;
  WOWorkersCount = 3;

  SOGoSuperUsernames = ("${ADMIN_EMAIL}");

  SOGoUserSources = (
    {
      type = sql;
      id = directory;
      viewURL = "mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}/sogo_view";
      canAuthenticate = YES;
      isAddressBook = YES;
      userPasswordAlgorithm = none;
      MailFieldNames = (mail);
    }
  );

  SoLogFile = "/var/log/sogo/sogo.log";
}
EOF

    chown root:sogo /etc/sogo/sogo.conf
    chmod 640 /etc/sogo/sogo.conf

    cat > /etc/default/sogo << EOF
PREFORK=3
EOF

    systemctl daemon-reload
    systemctl restart sogo
    sleep 3

    if systemctl is-active --quiet sogo; then
        log_ok "SOGo démarré avec succès."
    else
        log_err "SOGo a échoué. Vérifiez : journalctl -u sogo"
    fi
    pause
}

# ============================================================
# ÉTAPE 6 : CONFIGURATION APACHE
# ============================================================
config_apache() {
    show_header
    echo -e "${GREEN}=== ÉTAPE 6 : Configuration d'Apache ===${NC}"
    echo ""

    a2enmod proxy proxy_http alias headers rewrite 2>/dev/null

    cat > /etc/apache2/sites-available/sogo.conf << EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}

    Alias /SOGo.woa/WebServerResources /usr/share/GNUstep/SOGo/WebServerResources
    <Directory /usr/share/GNUstep/SOGo/WebServerResources>
        Require all granted
        Options FollowSymLinks
    </Directory>

    ProxyPreserveHost On
    ProxyPass /SOGo.woa/WebServerResources !
    ProxyPass / http://127.0.0.1:20000/
    ProxyPassReverse / http://127.0.0.1:20000/

    Timeout 600
    LimitRequestBody 104857600

    ErrorLog \${APACHE_LOG_DIR}/sogo_error.log
    CustomLog \${APACHE_LOG_DIR}/sogo_access.log combined
</VirtualHost>
EOF

    a2dissite 000-default.conf 2>/dev/null
    a2ensite sogo.conf 2>/dev/null
    systemctl restart apache2

    log_ok "Apache configuré."
    pause
}

# ============================================================
# GESTION DES UTILISATEURS
# ============================================================
add_user() {
    show_header
    echo -e "${GREEN}=== AJOUT D'UN UTILISATEUR ===${NC}"
    echo ""

    local user_email user_name user_pass user_cn

    while [ -z "$user_email" ]; do
        read -p "Email (ex: prenom@${DOMAIN}) : " user_email
    done
    while [ -z "$user_name" ]; do
        read -p "Nom d'utilisateur (login court) : " user_name
    done
    while [ -z "$user_pass" ]; do
        read -sp "Mot de passe : " user_pass
        echo ""
    done
    while [ -z "$user_cn" ]; do
        read -p "Nom complet : " user_cn
    done

    # Ajouter dans MySQL (SOGo)
    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" << EOF
INSERT INTO sogo_view (c_uid, c_name, c_password, c_cn, mail)
VALUES ('${user_email}', '${user_name}', '${user_pass}', '${user_cn}', '${user_email}')
ON DUPLICATE KEY UPDATE c_password='${user_pass}', c_cn='${user_cn}';
EOF

    # Ajouter dans Dovecot passwd-file
    if grep -q "^${user_email}:" /etc/dovecot/users 2>/dev/null; then
        sed -i "s|^${user_email}:.*|${user_email}:${user_pass}|" /etc/dovecot/users
        log_info "Mot de passe mis à jour dans Dovecot."
    else
        echo "${user_email}:${user_pass}" >> /etc/dovecot/users
        log_ok "Utilisateur ajouté dans Dovecot."
    fi

    # Créer le dossier maildir
    mkdir -p "/var/mail/${user_email}/{cur,new,tmp}"
    chown -R vmail:vmail "/var/mail/${user_email}"

    # Ajouter dans Postfix vmailbox
    if ! grep -q "^${user_email}" /etc/postfix/vmailbox 2>/dev/null; then
        echo "${user_email}    ${user_email}/" >> /etc/postfix/vmailbox
        postmap /etc/postfix/vmailbox
        postfix reload 2>/dev/null
        log_ok "Utilisateur ajouté dans Postfix."
    fi

    echo ""
    log_ok "Utilisateur ${user_email} créé avec succès !"
    echo -e "  Login : ${CYAN}${user_email}${NC}"
    echo -e "  Pass  : ${CYAN}${user_pass}${NC}"
    pause
}

list_users() {
    show_header
    echo -e "${GREEN}=== LISTE DES UTILISATEURS ===${NC}"
    echo ""
    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -e "SELECT c_uid AS 'Email', c_cn AS 'Nom complet', mail AS 'Adresse mail' FROM sogo_view;" 2>/dev/null
    echo ""
    echo -e "${YELLOW}Fichier Dovecot (/etc/dovecot/users) :${NC}"
    cat /etc/dovecot/users 2>/dev/null | sed 's/:.*/ [mot de passe masqué]/'
    pause
}

delete_user() {
    show_header
    echo -e "${GREEN}=== SUPPRESSION D'UN UTILISATEUR ===${NC}"
    echo ""
    local user_email
    read -p "Email de l'utilisateur à supprimer : " user_email

    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -e "DELETE FROM sogo_view WHERE c_uid='${user_email}';" 2>/dev/null

    sed -i "/^${user_email}:/d" /etc/dovecot/users 2>/dev/null

    sed -i "/^${user_email}/d" /etc/postfix/vmailbox 2>/dev/null
    postmap /etc/postfix/vmailbox
    postfix reload 2>/dev/null

    log_ok "Utilisateur ${user_email} supprimé."
    log_warn "Le dossier mail /var/mail/${user_email} n'a pas été supprimé (sauvegarde)."
    pause
}

change_password() {
    show_header
    echo -e "${GREEN}=== CHANGER LE MOT DE PASSE ===${NC}"
    echo ""
    local user_email user_pass
    read -p "Email de l'utilisateur : " user_email
    read -sp "Nouveau mot de passe : " user_pass
    echo ""

    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -e "UPDATE sogo_view SET c_password='${user_pass}' WHERE c_uid='${user_email}';" 2>/dev/null

    sed -i "s|^${user_email}:.*|${user_email}:${user_pass}|" /etc/dovecot/users 2>/dev/null

    log_ok "Mot de passe modifié pour ${user_email}."
    pause
}

# ============================================================
# MAINTENANCE
# ============================================================
check_status() {
    show_header
    echo -e "${GREEN}=== STATUT DES SERVICES ===${NC}"
    echo ""

    for svc in sogo dovecot postfix apache2 mariadb memcached; do
        if systemctl is-active --quiet "$svc"; then
            echo -e "  ${GREEN}●${NC} $svc : ${GREEN}actif${NC}"
        else
            echo -e "  ${RED}●${NC} $svc : ${RED}inactif${NC}"
        fi
    done

    echo ""
    echo -e "${CYAN}Ports en écoute :${NC}"
    ss -tlnp | grep -E ":(25|143|80|20000|3306)\s" | awk '{print "  "$1" "$4}' 2>/dev/null

    echo ""
    IP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}URL SOGo : http://${IP}/SOGo${NC}"
    pause
}

test_smtp() {
    show_header
    echo -e "${GREEN}=== TEST SMTP ===${NC}"
    echo ""
    local from_email to_email
    read -p "Expéditeur : " from_email
    read -p "Destinataire : " to_email

    sendmail -v "$to_email" << EOF
From: ${from_email}
To: ${to_email}
Subject: Test SMTP depuis le serveur

Ceci est un email de test envoyé depuis le script d'installation.
EOF

    sleep 2
    log_info "Vérification de la boîte de réception..."
    ls "/var/mail/${to_email}/new/" 2>/dev/null && log_ok "Email reçu !" || log_warn "Aucun email trouvé dans /var/mail/${to_email}/new/"
    pause
}

test_imap() {
    show_header
    echo -e "${GREEN}=== TEST IMAP (Dovecot) ===${NC}"
    echo ""
    local user_email user_pass
    read -p "Email à tester : " user_email
    read -sp "Mot de passe : " user_pass
    echo ""

    result=$(doveadm auth test "$user_email" "$user_pass" 2>&1)
    if echo "$result" | grep -q "auth succeeded"; then
        log_ok "Authentification IMAP réussie pour ${user_email} !"
    else
        log_err "Authentification échouée."
        echo "$result"
    fi
    pause
}

view_logs() {
    show_header
    echo -e "${GREEN}=== LOGS DES SERVICES ===${NC}"
    echo ""
    echo "1. Logs SOGo"
    echo "2. Logs Postfix"
    echo "3. Logs Dovecot"
    echo ""
    read -p "Choix : " LOG_CHOICE
    case $LOG_CHOICE in
        1) tail -30 /var/log/sogo/sogo.log 2>/dev/null ;;
        2) journalctl -u postfix --since "1 hour ago" --no-pager | tail -30 ;;
        3) journalctl -u dovecot --since "1 hour ago" --no-pager | tail -30 ;;
    esac
    pause
}

restart_all() {
    show_header
    echo -e "${GREEN}=== REDÉMARRAGE DE TOUS LES SERVICES ===${NC}"
    echo ""
    for svc in mariadb memcached postfix dovecot apache2 sogo; do
        systemctl restart "$svc" 2>/dev/null && log_ok "$svc redémarré." || log_err "$svc a échoué."
    done
    pause
}

fix_permissions() {
    show_header
    echo -e "${GREEN}=== CORRECTION DES PERMISSIONS ===${NC}"
    echo ""
    chown -R vmail:vmail /var/mail/
    chmod -R 770 /var/mail/
    chmod 644 /etc/dovecot/users
    chown root:sogo /etc/sogo/sogo.conf
    chmod 640 /etc/sogo/sogo.conf
    chown -R sogo:sogo /var/log/sogo /run/sogo 2>/dev/null
    log_ok "Permissions corrigées."
    pause
}

show_info() {
    show_header
    IP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                  INFORMATIONS DE CONNEXION                  ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  URL SOGo     : http://${IP}/SOGo                   ${NC}"
    echo -e "${BLUE}║  Domaine      : ${DOMAIN}                           ${NC}"
    echo -e "${BLUE}║  Admin        : ${ADMIN_EMAIL}                      ${NC}"
    echo -e "${BLUE}║  DB Name      : ${DB_NAME}                          ${NC}"
    echo -e "${BLUE}║  DB User      : ${DB_USER}                          ${NC}"
    echo -e "${BLUE}║  IMAP         : ${IP}:143                           ${NC}"
    echo -e "${BLUE}║  SMTP         : ${IP}:25                            ${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Utilisateurs SOGo :${NC}"
    mysql -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -e "SELECT c_uid, c_cn FROM sogo_view;" 2>/dev/null
    pause
}

# ============================================================
# INSTALLATION COMPLÈTE AUTOMATIQUE
# ============================================================
full_install() {
    collect_params
    install_dependencies
    config_database
    config_dovecot
    config_postfix
    config_sogo
    config_apache

    show_header
    IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         INSTALLATION TERMINÉE AVEC SUCCÈS !                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}URL SOGo    :${NC} http://${IP}/SOGo"
    echo -e "  ${CYAN}Admin login :${NC} ${ADMIN_EMAIL}"
    echo -e "  ${CYAN}Admin pass  :${NC} ${ADMIN_PASS}"
    echo ""
    echo -e "${YELLOW}Pour ajouter des utilisateurs, relancez ce script → Menu → Option 7${NC}"
    pause
}

# ============================================================
# MENU PRINCIPAL
# ============================================================
main_menu() {
    # Charger les variables si déjà configurées
    while true; do
        show_header
        echo -e "${GREEN}=== MENU PRINCIPAL ===${NC}"
        echo ""
        echo -e "${CYAN}── Installation ──────────────────────────────────${NC}"
        echo "  1.  Installation complète automatique (recommandée)"
        echo "  2.  Saisir les paramètres uniquement"
        echo "  3.  Installer les dépendances"
        echo "  4.  Configurer la base de données"
        echo "  5.  Configurer Dovecot (IMAP)"
        echo "  6.  Configurer Postfix (SMTP)"
        echo "  7.  Configurer SOGo"
        echo "  8.  Configurer Apache"
        echo ""
        echo -e "${CYAN}── Utilisateurs ──────────────────────────────────${NC}"
        echo "  9.  Ajouter un utilisateur"
        echo "  10. Lister les utilisateurs"
        echo "  11. Supprimer un utilisateur"
        echo "  12. Changer le mot de passe"
        echo ""
        echo -e "${CYAN}── Maintenance ───────────────────────────────────${NC}"
        echo "  13. Statut des services"
        echo "  14. Tester SMTP (envoi email)"
        echo "  15. Tester IMAP (auth Dovecot)"
        echo "  16. Voir les logs"
        echo "  17. Redémarrer tous les services"
        echo "  18. Corriger les permissions"
        echo "  19. Informations de connexion"
        echo ""
        echo "  0.  Quitter"
        echo ""
        read -p "Votre choix : " CHOICE

        case $CHOICE in
            1)  full_install ;;
            2)  collect_params ;;
            3)  install_dependencies ;;
            4)  config_database ;;
            5)  config_dovecot ;;
            6)  config_postfix ;;
            7)  config_sogo ;;
            8)  config_apache ;;
            9)  add_user ;;
            10) list_users ;;
            11) delete_user ;;
            12) change_password ;;
            13) check_status ;;
            14) test_smtp ;;
            15) test_imap ;;
            16) view_logs ;;
            17) restart_all ;;
            18) fix_permissions ;;
            19) show_info ;;
            0)
                echo -e "${GREEN}Au revoir !${NC}"
                exit 0
                ;;
            *)
                log_err "Option invalide."
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# POINT D'ENTRÉE
# ============================================================
check_root
main_menu
