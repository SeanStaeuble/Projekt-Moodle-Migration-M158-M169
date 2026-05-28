#!/bin/bash
# =============================================================
#  Moodle Migration Script – Interaktiv
#  Projekt: Moodle-Migration auf Docker
#  Team: Julian, Sean, Noa
# =============================================================

set -e

# Farben fuer Ausgabe
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
# SCHRITT 1: Eingaben vom Benutzer abfragen
# -------------------------------------------------------
echo -e "${GELB}[1/6] Konfiguration eingeben${NC}"
echo ""

# Altes Moodle-Verzeichnis
read -p "Pfad zum alten Moodle-Verzeichnis [/var/www/html/moodle]: " ALTES_MOODLE
ALTES_MOODLE=${ALTES_MOODLE:-/var/www/html/moodle}

# Altes moodledata-Verzeichnis
read -p "Pfad zum alten moodledata-Verzeichnis [/var/moodledata]: " ALTES_MOODLEDATA
ALTES_MOODLEDATA=${ALTES_MOODLEDATA:-/var/moodledata}

# Datenbankname der alten Instanz
read -p "Datenbankname der alten Moodle-Instanz [moodle]: " ALTE_DB
ALTE_DB=${ALTE_DB:-moodle}

# MySQL/MariaDB Root-Passwort (alte Instanz)
read -s -p "MySQL Root-Passwort der alten Instanz: " ALTES_DB_PASS
echo ""

# Port-Konfiguration
read -p "Port fuer NEUE Moodle-Instanz [80]: " PORT_NEU
PORT_NEU=${PORT_NEU:-80}

read -p "Port fuer ALTE Moodle-Instanz [8080]: " PORT_ALT
PORT_ALT=${PORT_ALT:-8080}

# Neue DB-Zugangsdaten
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
echo -e "${GELB}[2/6] Voraussetzungen pruefen${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${ROT}FEHLER: Docker ist nicht installiert!${NC}"
    echo "Installieren mit: sudo apt-get install docker.io"
    exit 1
fi

if ! command -v docker compose version &> /dev/null 2>&1; then
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
echo -e "${GELB}[3/6] .env Datei erstellen${NC}"

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

echo -e "${GRUEN}.env erstellt unter: $CONFIG_DIR/.env${NC}"

# -------------------------------------------------------
# SCHRITT 4: Datenbank-Dump erstellen und importieren
# -------------------------------------------------------
echo -e "${GELB}[4/6] Datenbankdump erstellen${NC}"

DUMP_DATEI="$SCRIPT_DIR/dump_alt.sql"

echo "Erstelle Dump aus alter Datenbank..."
mysqldump -u root -p"$ALTES_DB_PASS" "$ALTE_DB" > "$DUMP_DATEI"

if [ ! -s "$DUMP_DATEI" ]; then
    echo -e "${ROT}FEHLER: Dump-Datei ist leer oder konnte nicht erstellt werden!${NC}"
    exit 1
fi

echo -e "${GRUEN}Dump erstellt: $DUMP_DATEI${NC}"

# -------------------------------------------------------
# SCHRITT 5: Docker Container starten und Daten importieren
# -------------------------------------------------------
echo -e "${GELB}[5/6] Docker Container starten${NC}"

cd "$CONFIG_DIR"

# Nur Datenbank-Container zuerst starten
echo "Starte Datenbank-Container..."
docker compose up -d moodle_db

echo "Warte auf Datenbank (30 Sekunden)..."
sleep 30

# Dump importieren
echo "Importiere Dump in neuen Container..."
docker exec -i moodle_db mariadb \
    -u"$NEUE_DB_USER" \
    -p"$NEUE_DB_PASS" \
    "$NEUE_DB" < "$DUMP_DATEI"

echo -e "${GRUEN}Dump importiert.${NC}"

# Moodle-Container starten
echo "Starte Moodle-Container..."
docker compose up -d moodle_neu

echo "Warte auf Moodle-Container (20 Sekunden)..."
sleep 20

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

# Datenbank-Schema upgraden
echo "Fuehre Moodle-Upgrade durch..."
docker exec moodle_neu bash -c \
    "php /var/www/html/moodle/admin/cli/upgrade.php --non-interactive" \
    && echo -e "${GRUEN}Upgrade abgeschlossen.${NC}" \
    || echo -e "${GELB}WARNUNG: Upgrade-Befehl mit Fehler beendet – manuell pruefen!${NC}"

# -------------------------------------------------------
# SCHRITT 6: Alte Instanz auf Port 8080 umstellen
# -------------------------------------------------------
echo -e "${GELB}[6/6] Alte Instanz auf Port $PORT_ALT umstellen${NC}"

echo "Stoppe Apache..."
sudo systemctl stop apache2

echo "Aendere Apache-Port auf $PORT_ALT..."
sudo sed -i "s/Listen 80$/Listen $PORT_ALT/" /etc/apache2/ports.conf
sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$PORT_ALT>/" \
    /etc/apache2/sites-enabled/*.conf 2>/dev/null || true

# wwwroot in alter config.php anpassen
ALTE_CONFIG="$ALTES_MOODLE/config.php"
if [ -f "$ALTE_CONFIG" ]; then
    sudo sed -i "s|wwwroot\s*=\s*'http://localhost'|wwwroot = 'http://localhost:$PORT_ALT'|g" \
        "$ALTE_CONFIG"
    echo -e "${GRUEN}config.php angepasst.${NC}"
fi

# Warnbanner in alte config.php einfuegen
echo "Fuge Warnbanner zur alten Instanz hinzu..."
sudo tee /tmp/banner_insert.php > /dev/null <<'BANNER'

// Warnbanner fuer veraltete Instanz
$CFG->additionalhtmltopofbody = '<div style="background:#c0392b;color:#fff;text-align:center;padding:12px;font-size:16px;font-weight:bold;">ACHTUNG: Diese Moodle-Instanz ist veraltet (Version 3.10, End of Life seit Oktober 2022). Keine Sicherheits-Updates mehr! Bitte die neue Instanz unter http://localhost verwenden.</div>';

BANNER

sudo sed -i "/require_once/r /tmp/banner_insert.php" "$ALTE_CONFIG"

echo "Starte Apache neu..."
sudo systemctl start apache2

# -------------------------------------------------------
# Abschluss
# -------------------------------------------------------
echo ""
echo -e "${BLAU}=============================================${NC}"
echo -e "${GRUEN}  Migration abgeschlossen!${NC}"
echo -e "${BLAU}=============================================${NC}"
echo ""
echo -e "  Neue Instanz:  ${GRUEN}http://localhost:$PORT_NEU${NC}"
echo -e "  Alte Instanz:  ${GELB}http://localhost:$PORT_ALT${NC}  (mit Warnbanner)"
echo ""
echo -e "${GELB}Naechste Schritte:${NC}"
echo "  1. http://localhost:$PORT_NEU im Browser oeffnen"
echo "  2. Mit migriertem Benutzer einloggen"
echo "  3. Kurse und Inhalte pruefen"
echo "  4. Testbenutzer loeschen (falls erstellt)"
echo ""

# Dump-Datei aufraumen
read -p "Dump-Datei loeschen? (j/n) [j]: " LOESCHEN
LOESCHEN=${LOESCHEN:-j}
if [[ "$LOESCHEN" == "j" || "$LOESCHEN" == "J" ]]; then
    rm -f "$DUMP_DATEI"
    echo -e "${GRUEN}Dump-Datei geloescht.${NC}"
fi

echo "Fertig."
