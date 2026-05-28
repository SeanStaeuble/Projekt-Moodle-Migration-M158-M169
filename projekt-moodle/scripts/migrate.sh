#!/bin/bash
# =============================================================
#  Moodle Migration Script – Interaktiv
#  Projekt: Moodle-Migration auf Docker
#  Team: Julian, Sean, Noa
# =============================================================

set -e

ROT='\033[0;31m'
GRUEN='\033[0;32m'
GELB='\033[1;33m'
BLAU='\033[0;34m'
NC='\033[0m'

echo -e "${BLAU}=============================================${NC}"
echo -e "${BLAU}   Moodle Migration – Interaktives Setup     ${NC}"
echo -e "${BLAU}=============================================${NC}"
echo ""

# -------------------------------------------------------
# SCHRITT 1: Eingaben
# -------------------------------------------------------
echo -e "${GELB}[1/7] Konfiguration eingeben${NC}"
echo ""

read -p "Pfad zum alten Moodle-Verzeichnis [/var/www/html]: " ALTES_MOODLE
ALTES_MOODLE=${ALTES_MOODLE:-/var/www/html}

read -p "Pfad zum alten moodledata-Verzeichnis [/var/www/moodledata]: " ALTES_MOODLEDATA
ALTES_MOODLEDATA=${ALTES_MOODLEDATA:-/var/www/moodledata}

read -p "Datenbankname der alten Moodle-Instanz [moodle]: " ALTE_DB
ALTE_DB=${ALTE_DB:-moodle}

read -s -p "MySQL Root-Passwort der alten Instanz: " ALTES_DB_PASS
echo ""

read -p "Port fuer NEUE Moodle-Instanz [80]: " PORT_NEU
PORT_NEU=${PORT_NEU:-80}

read -p "Port fuer ALTE Moodle-Instanz [8080]: " PORT_ALT
PORT_ALT=${PORT_ALT:-8080}

echo ""
echo "Zugangsdaten fuer den neuen MariaDB-Container:"
read -p "  Datenbankname [moodledb]: " NEUE_DB
NEUE_DB=${NEUE_DB:-moodledb}

read -p "  Datenbankbenutzer [moodleuser]: " NEUE_DB_USER
NEUE_DB_USER=${NEUE_DB_USER:-moodleuser}

read -s -p "  Datenbankpasswort: " NEUE_DB_PASS
echo ""

read -s -p "  MariaDB Root-Passwort (neu): " NEUE_DB_ROOT
echo ""

echo ""
echo -e "${GRUEN}Konfiguration gespeichert. Weiter mit Enter...${NC}"
read

# -------------------------------------------------------
# SCHRITT 2: Voraussetzungen pruefen
# -------------------------------------------------------
echo -e "${GELB}[2/7] Voraussetzungen pruefen${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${ROT}FEHLER: Docker ist nicht installiert!${NC}"
    exit 1
fi

if ! docker compose version &> /dev/null 2>&1; then
    echo -e "${ROT}FEHLER: Docker Compose ist nicht installiert!${NC}"
    exit 1
fi

if [ ! -d "$ALTES_MOODLE" ]; then
    echo -e "${ROT}FEHLER: Moodle-Verzeichnis nicht gefunden: $ALTES_MOODLE${NC}"
    exit 1
fi

if [ ! -d "$ALTES_MOODLEDATA" ]; then
    echo -e "${ROT}FEHLER: moodledata nicht gefunden: $ALTES_MOODLEDATA${NC}"
    exit 1
fi

echo -e "${GRUEN}Alle Voraussetzungen erfuellt.${NC}"

# -------------------------------------------------------
# SCHRITT 3: .env Datei erstellen
# -------------------------------------------------------
echo -e "${GELB}[3/7] .env Datei erstellen${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

cat > "$CONFIG_DIR/.env" <<EOF
DB_ROOT_PASS=$NEUE_DB_ROOT
DB_NAME=$NEUE_DB
DB_USER=$NEUE_DB_USER
DB_PASS=$NEUE_DB_PASS
PORT_NEU=$PORT_NEU
PORT_ALT=$PORT_ALT
EOF

echo -e "${GRUEN}.env erstellt.${NC}"

# -------------------------------------------------------
# SCHRITT 4: Datenbank-Dump erstellen
# -------------------------------------------------------
echo -e "${GELB}[4/7] Datenbankdump erstellen${NC}"

DUMP_DATEI="$SCRIPT_DIR/dump_alt.sql"

echo "Erstelle Dump aus alter Datenbank..."
mysqldump -u root -p"$ALTES_DB_PASS" "$ALTE_DB" > "$DUMP_DATEI"

if [ ! -s "$DUMP_DATEI" ]; then
    echo -e "${ROT}FEHLER: Dump leer oder fehlgeschlagen!${NC}"
    exit 1
fi

echo -e "${GRUEN}Dump erstellt: $DUMP_DATEI${NC}"

# -------------------------------------------------------
# SCHRITT 5: Docker Container starten und Daten importieren
# -------------------------------------------------------
echo -e "${GELB}[5/7] Docker Container starten${NC}"

cd "$CONFIG_DIR"

echo "Starte Datenbank-Container..."
docker compose up -d moodle_db

echo "Warte auf Datenbank (30 Sekunden)..."
sleep 30

echo "Importiere Dump..."
docker exec -i moodle_db mariadb \
    -u root \
    -p"$NEUE_DB_ROOT" \
    "$NEUE_DB" < "$DUMP_DATEI"

echo -e "${GRUEN}Dump importiert.${NC}"

echo "Starte Moodle-Container..."
docker compose up -d moodle_neu

echo "Warte auf Moodle-Container (20 Sekunden)..."
sleep 20

# -------------------------------------------------------
# SCHRITT 6: Schrittweises Upgrade 3.10 -> 4.1 -> 4.5
# -------------------------------------------------------
echo -e "${GELB}[6/7] Schrittweises Moodle-Upgrade${NC}"

# PHP max_input_vars fix
docker exec moodle_neu bash -c "echo 'max_input_vars = 5000' >> /etc/php/8.1/cli/php.ini"

CONFIG_PHP='<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();
$CFG->dbtype    = '"'"'mariadb'"'"';
$CFG->dblibrary = '"'"'native'"'"';
$CFG->dbhost    = '"'"'moodle_db'"'"';
$CFG->dbname    = '"'"''"$NEUE_DB"''"'"';
$CFG->dbuser    = '"'"''"$NEUE_DB_USER"''"'"';
$CFG->dbpass    = '"'"''"$NEUE_DB_PASS"''"'"';
$CFG->prefix    = '"'"'mdl_'"'"';
$CFG->wwwroot   = '"'"'http://localhost'"'"';
$CFG->dataroot  = '"'"'/var/moodledata'"'"';
$CFG->directorypermissions = 0777;
$CFG->admin = '"'"'admin'"'"';
require_once(__DIR__ . '"'"'/lib/setup.php'"'"');'

# Upgrade auf 4.1
echo "Installiere Moodle 4.1 fuer Zwischenupgrade..."
docker exec moodle_neu bash -c "
    rm -rf /var/www/html/moodle &&
    wget -q 'https://download.moodle.org/download.php/direct/stable401/moodle-latest-401.tgz' -O /tmp/m401.tgz &&
    tar -xf /tmp/m401.tgz -C /var/www/html/ &&
    rm /tmp/m401.tgz &&
    chown -R www-data:www-data /var/www/html/moodle
"

docker exec moodle_neu bash -c "cat > /var/www/html/moodle/config.php << 'EOF'
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();
\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'moodle_db';
\$CFG->dbname    = '$NEUE_DB';
\$CFG->dbuser    = '$NEUE_DB_USER';
\$CFG->dbpass    = '$NEUE_DB_PASS';
\$CFG->prefix    = 'mdl_';
\$CFG->wwwroot   = 'http://localhost';
\$CFG->dataroot  = '/var/moodledata';
\$CFG->directorypermissions = 0777;
\$CFG->admin = 'admin';
require_once(__DIR__ . '/lib/setup.php');
EOF"

echo "Upgrade auf 4.1..."
docker exec moodle_neu php /var/www/html/moodle/admin/cli/upgrade.php --non-interactive
echo -e "${GRUEN}Upgrade auf 4.1 abgeschlossen.${NC}"

# Upgrade auf 4.5
echo "Installiere Moodle 4.5..."
docker exec moodle_neu bash -c "
    rm -rf /var/www/html/moodle &&
    wget -q 'https://download.moodle.org/download.php/direct/stable405/moodle-latest-405.tgz' -O /tmp/m405.tgz &&
    tar -xf /tmp/m405.tgz -C /var/www/html/ &&
    rm /tmp/m405.tgz &&
    chown -R www-data:www-data /var/www/html/moodle
"

docker exec moodle_neu bash -c "cat > /var/www/html/moodle/config.php << 'EOF'
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();
\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'moodle_db';
\$CFG->dbname    = '$NEUE_DB';
\$CFG->dbuser    = '$NEUE_DB_USER';
\$CFG->dbpass    = '$NEUE_DB_PASS';
\$CFG->prefix    = 'mdl_';
\$CFG->wwwroot   = 'http://localhost';
\$CFG->dataroot  = '/var/moodledata';
\$CFG->directorypermissions = 0777;
\$CFG->admin = 'admin';
require_once(__DIR__ . '/lib/setup.php');
EOF"

echo "Upgrade auf 4.5..."
docker exec moodle_neu php /var/www/html/moodle/admin/cli/upgrade.php --non-interactive
echo -e "${GRUEN}Upgrade auf 4.5 abgeschlossen.${NC}"

# moodledata kopieren
echo "Kopiere moodledata..."
VOLUME_NAME=$(docker inspect moodle_neu --format '{{range .Mounts}}{{if eq .Destination "/var/moodledata"}}{{.Name}}{{end}}{{end}}')
if [ -n "$VOLUME_NAME" ]; then
    docker run --rm \
        -v "$ALTES_MOODLEDATA":/quelle:ro \
        -v "$VOLUME_NAME":/ziel \
        ubuntu:22.04 \
        bash -c "cp -a /quelle/. /ziel/ && chown -R 33:33 /ziel"
    echo -e "${GRUEN}moodledata kopiert.${NC}"
else
    echo -e "${GELB}WARNUNG: Volume nicht gefunden, moodledata manuell kopieren!${NC}"
fi

# -------------------------------------------------------
# SCHRITT 7: Alte Instanz auf Port 8080
# -------------------------------------------------------
echo -e "${GELB}[7/7] Alte Instanz auf Port $PORT_ALT umstellen${NC}"

sudo sed -i '/^Listen 80$/d' /etc/apache2/ports.conf
echo "Listen $PORT_ALT" | sudo tee -a /etc/apache2/ports.conf > /dev/null

sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$PORT_ALT>/" \
    /etc/apache2/sites-enabled/*.conf 2>/dev/null || true

ALTE_CONFIG="$ALTES_MOODLE/config.php"
if [ -f "$ALTE_CONFIG" ]; then
    sudo sed -i "s|wwwroot\s*=\s*'http://localhost'|wwwroot = 'http://localhost:$PORT_ALT'|g" "$ALTE_CONFIG"
fi

sudo tee /tmp/banner_insert.php > /dev/null <<'BANNER'
$CFG->additionalhtmltopofbody = '<div style="background:#c0392b;color:#fff;text-align:center;padding:12px;font-size:16px;font-weight:bold;">ACHTUNG: Diese Moodle-Instanz ist veraltet (Version 3.10). Bitte die neue Instanz unter http://localhost verwenden.</div>';
BANNER

sudo sed -i "/require_once/r /tmp/banner_insert.php" "$ALTE_CONFIG"
sudo systemctl restart apache2

# Abschluss
echo ""
echo -e "${BLAU}=============================================${NC}"
echo -e "${GRUEN}  Migration abgeschlossen!${NC}"
echo -e "${BLAU}=============================================${NC}"
echo ""
echo -e "  Neue Instanz:  ${GRUEN}http://localhost:$PORT_NEU${NC}"
echo -e "  Alte Instanz:  ${GELB}http://localhost:$PORT_ALT${NC}"
echo ""

read -p "Dump-Datei loeschen? (j/n) [j]: " LOESCHEN
LOESCHEN=${LOESCHEN:-j}
if [[ "$LOESCHEN" == "j" || "$LOESCHEN" == "J" ]]; then
    rm -f "$DUMP_DATEI"
    echo -e "${GRUEN}Dump-Datei geloescht.${NC}"
fi

echo "Fertig."
