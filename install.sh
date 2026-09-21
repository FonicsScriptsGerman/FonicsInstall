#!/bin/bash

# ============================================================
# FiveM FXServer Installer
# Game Port : 40200 TCP/UDP
# txAdmin   : 40201 TCP
# Install   : /home/fivem/server
# Data      : /home/fivem/server-data
# Service   : fivem.service
# ============================================================

set -e

FIVEM_USER="fivem"
FIVEM_HOME="/home/fivem"
SERVER_DIR="/home/fivem/server"
DATA_DIR="/home/fivem/server-data"

GAME_PORT="30200"
TXADMIN_PORT="40200"

ARTIFACT_BASE="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master"
SERVICE_FILE="/etc/systemd/system/fivem.service"

if [ "$EUID" -ne 0 ]; then
    echo "Bitte als root ausführen, z.B.: sudo bash install.sh"
    exit 1
fi

echo ""
echo "=============================================="
echo "        FiveM FXServer Installation"
echo "=============================================="
echo "Game Port : $GAME_PORT TCP/UDP"
echo "txAdmin   : $TXADMIN_PORT TCP"
echo ""

echo "[1/10] System aktualisieren..."
apt-get update -y
apt-get upgrade -y

echo "[2/10] Abhängigkeiten installieren..."
apt-get install -y curl wget xz-utils tar git ca-certificates unzip jq ufw screen nano

echo "[3/10] FiveM Benutzer erstellen..."
if ! id "$FIVEM_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$FIVEM_HOME" --shell /bin/bash "$FIVEM_USER"
fi

mkdir -p "$SERVER_DIR" "$DATA_DIR"
chown -R "$FIVEM_USER:$FIVEM_USER" "$FIVEM_HOME"

echo "[4/10] Aktuelles FiveM Artifact suchen..."
ARTIFACT_PAGE=$(curl -fsSL "$ARTIFACT_BASE/")

ARTIFACT_FILE=$(echo "$ARTIFACT_PAGE" \
    | grep -oE 'href="[^"]+fx\.tar\.xz"' \
    | sed 's/href="//' \
    | sed 's/"//' \
    | tail -n 1)

if [ -z "$ARTIFACT_FILE" ]; then
    echo "FEHLER: Kein FiveM Artifact gefunden."
    echo "Artifact-Seite: $ARTIFACT_BASE"
    exit 1
fi

if [[ "$ARTIFACT_FILE" == http* ]]; then
    ARTIFACT_URL="$ARTIFACT_FILE"
elif [[ "$ARTIFACT_FILE" == /* ]]; then
    ARTIFACT_URL="https://runtime.fivem.net$ARTIFACT_FILE"
else
    ARTIFACT_URL="$ARTIFACT_BASE/$ARTIFACT_FILE"
fi

echo "Artifact: $ARTIFACT_URL"

echo "[5/10] FiveM Artifact herunterladen..."
rm -rf "$SERVER_DIR"/*
cd "$SERVER_DIR"
wget --progress=bar:force -O fx.tar.xz "$ARTIFACT_URL"

echo "[6/10] FiveM Artifact entpacken..."
tar -xf fx.tar.xz
rm -f fx.tar.xz
chown -R "$FIVEM_USER:$FIVEM_USER" "$SERVER_DIR"

echo "[7/10] server.cfg erstellen..."
cat > "$DATA_DIR/server.cfg" <<EOF
# ============================================================
# FiveM Server Configuration
# ============================================================

endpoint_add_udp "0.0.0.0:${GAME_PORT}"
endpoint_add_tcp "0.0.0.0:${GAME_PORT}"

sv_hostname "Mein FiveM Server"
sv_maxclients 48

sets locale "de-DE"
sets tags "germany,deutsch,roleplay,fivem"
sets sv_projectDesc "Mein eigener FiveM Server"
sets sv_projectName "Mein FiveM Server"

sv_scriptHookAllowed 0
set onesync on

# set steam_webApiKey "DEIN_STEAM_API_KEY"

# Cfx.re Server-Key hier eintragen:
sv_licenseKey "CHANGE_ME"

ensure mapmanager
ensure chat
ensure spawnmanager
ensure sessionmanager
ensure basic-gamemode
ensure hardcap
ensure rconlog

setr voice_useNativeAudio true
setr voice_useSendingRangeOnly true

set logfile "server.log"
EOF

chown "$FIVEM_USER:$FIVEM_USER" "$DATA_DIR/server.cfg"

echo "[8/10] txAdmin vorbereiten..."
mkdir -p "$DATA_DIR"
chown -R "$FIVEM_USER:$FIVEM_USER" "$DATA_DIR"

echo "[9/10] systemd Service erstellen..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=FiveM FXServer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${FIVEM_USER}
Group=${FIVEM_USER}
WorkingDirectory=${DATA_DIR}
ExecStart=${SERVER_DIR}/run.sh +exec server.cfg +set txAdminPort ${TXADMIN_PORT}
Restart=always
RestartSec=5
LimitNOFILE=1048576
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

echo "[10/10] Firewall konfigurieren..."
ufw allow 22/tcp
ufw allow "${GAME_PORT}/tcp"
ufw allow "${GAME_PORT}/udp"
ufw allow "${TXADMIN_PORT}/tcp"
ufw --force enable

systemctl daemon-reload
systemctl enable fivem.service
systemctl restart fivem.service

sleep 5

echo ""
echo "=============================================="
echo "           INSTALLATION FERTIG"
echo "=============================================="
echo ""
systemctl --no-pager --full status fivem.service || true

echo ""
echo "FiveM Game Port : ${GAME_PORT} TCP/UDP"
echo "txAdmin Port    : ${TXADMIN_PORT} TCP"
echo "Server          : ${SERVER_DIR}"
echo "Config          : ${DATA_DIR}/server.cfg"
echo ""
echo "Service-Befehle:"
echo "  systemctl start fivem"
echo "  systemctl stop fivem"
echo "  systemctl restart fivem"
echo "  systemctl status fivem"
echo "  journalctl -u fivem -f"
echo ""
echo "WICHTIG: Cfx.re Server-Key eintragen:"
echo "  nano ${DATA_DIR}/server.cfg"
echo ""
echo '  sv_licenseKey "DEIN_KEY"'
echo ""
echo "Danach:"
echo "  systemctl restart fivem"
echo ""
echo "txAdmin:"
echo "  http://SERVER-IP:${TXADMIN_PORT}"
echo ""
echo "FiveM:"
echo "  connect SERVER-IP:${GAME_PORT}"
echo ""
echo "Der Server startet nach einem Reboot automatisch."
echo ""
