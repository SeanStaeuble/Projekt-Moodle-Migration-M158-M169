# Moodle Migration – Docker

**Team:** Julian, Sean, Noa  
**Modul:** 158 / 169 – GBS St.Gallen

---

## Projektübersicht

Migration einer bestehenden Moodle-Instanz (~3.10) auf Moodle 4.4 in einem Docker-Container.

| | |
|---|---|
| Neue Instanz | `http://localhost:80` |
| Alte Instanz | `http://localhost:8080` (mit Warnbanner) |
| Datenbank | MariaDB 10.11 (Docker Container) |
| Webserver | Apache 2 (Ubuntu 22.04 Container) |
| PHP | 8.1 |

---

## Ordnerstruktur

```
projekt-moodle/
├── setup/          # Dockerfile, config.php, Apache-Konfiguration
├── config/         # docker-compose.yml, .env.example
├── scripts/        # Migrations-Script
└── README.md
```

---

## Voraussetzungen

- Linux VM mit SSH-Zugriff
- Docker + Docker Compose installiert
- Zugriff auf alte Moodle-Datenbank (MySQL Root-Passwort)
- `sudo`-Rechte

### Docker installieren
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER
# Neu einloggen danach
```

---

## Repository klonen

```bash
git clone https://github.com/<euer-repo>/projekt-moodle.git
cd projekt-moodle
chmod +x scripts/migrate.sh
```

---

## Migration durchführen

```bash
cd scripts
sudo ./migrate.sh
```

Das Script fragt interaktiv nach:
- Pfad zum alten Moodle-Verzeichnis
- Pfad zum alten moodledata-Verzeichnis
- Datenbankname der alten Instanz
- MySQL Root-Passwort (alte Instanz)
- Ports für neue und alte Instanz
- Zugangsdaten für die neue Datenbank

---

## Manueller Start (ohne Migration)

```bash
cd config
cp .env.example .env
# .env Datei anpassen
docker compose up -d
```

---

## Container verwalten

```bash
# Status prüfen
docker compose -f config/docker-compose.yml ps

# Logs anzeigen
docker logs moodle_neu
docker logs moodle_db

# Stoppen
docker compose -f config/docker-compose.yml down

# Neu starten
docker compose -f config/docker-compose.yml restart
```

---

## Sicherheit

- Keine echten Passwörter im Repository
- `.env` ist in `.gitignore` eingetragen
- Nur `.env.example` wird committed
