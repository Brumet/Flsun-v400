#!/bin/bash
# =============================================================================
#  RESCATE POR USB  -  FLSUN Speeder Pad
#
#  El pad ejecuta este fichero COMO ROOT en cada arranque si lo encuentra en
#  /home/pi/gcode_files/USB-Disk/ (lo lanza cfgguard.sh desde /etc/rc.local).
#
#  Sirve para recuperar el acceso cuando el pad se queda sin red y no hay
#  SSH, ni consola (Ctrl+Alt+F2 congela la pantalla), ni forma de entrar.
#
#  USO:
#    1. Copiar este update.sh a la raiz de una memoria USB
#    2. (Opcional) crear al lado un wifi.txt con dos lineas:
#           SSID=NombreDeLaRed
#           PASS=LaContrasena
#    3. Conectar el USB al pad y ENCENDER
#    4. Apagar, sacar el USB y leer rescate.log en la memoria
#
#  Sin wifi.txt: reactiva la red con la configuracion ya guardada.
#  Con wifi.txt: ademas anade esa red y la deja como preferida.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/rescate.log"
WPA="/etc/wpa_supplicant/wpa_supplicant.conf"
STAMP=$(date +%Y%m%d_%H%M%S)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

log "===== RESCATE INICIADO ($STAMP) ====="
log "host: $(hostname)  usuario: $(whoami)"

# --- 1. Quitar de en medio a NetworkManager -------------------------------
# Fue la causa de la perdida de acceso del 2026-09-15: tomaba wlan0 con una
# contrasena incorrecta y dejaba la maquina incomunicada.
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    log "NetworkManager activo -> deteniendo (causa conocida de bloqueo)"
    systemctl stop NetworkManager 2>&1 | tee -a "$LOG"
    systemctl disable NetworkManager 2>&1 | tee -a "$LOG"
else
    log "NetworkManager no activo - nada que hacer"
fi

# --- 2. Anadir la red nueva si viene wifi.txt ------------------------------
if [ -f "$DIR/wifi.txt" ]; then
    SSID=$(grep -E '^SSID=' "$DIR/wifi.txt" | head -1 | cut -d= -f2- | tr -d '\r')
    PASS=$(grep -E '^PASS=' "$DIR/wifi.txt" | head -1 | cut -d= -f2- | tr -d '\r')

    if [ -n "$SSID" ] && [ -n "$PASS" ]; then
        log "wifi.txt encontrado - red solicitada: '$SSID'"
        cp "$WPA" "${WPA}.bak_${STAMP}" 2>/dev/null && log "copia de seguridad: ${WPA}.bak_${STAMP}"

        # La red nueva va PRIMERO con prioridad alta, sin borrar las anteriores
        TMP=$(mktemp)
        {
            grep -E '^(ctrl_interface|update_config|country)' "$WPA" 2>/dev/null
            echo ""
            echo "network={"
            echo "	ssid=\"$SSID\""
            echo "	psk=\"$PASS\""
            echo "	key_mgmt=WPA-PSK"
            echo "	priority=99"
            echo "}"
            echo ""
            awk '/network=\{/{f=1} f' "$WPA" 2>/dev/null
        } > "$TMP"
        mv "$TMP" "$WPA"
        chmod 644 "$WPA"
        log "red '$SSID' anadida con prioridad 99"
    else
        log "ERROR: wifi.txt existe pero le faltan SSID= o PASS="
    fi
else
    log "sin wifi.txt - se reactiva la red ya configurada"
fi

# --- 3. Relanzar la red con el metodo propio del pad -----------------------
log "reiniciando wlan0..."
pkill -f "wpa_supplicant.*wlan0" 2>/dev/null
pkill dhclient 2>/dev/null
sleep 2

ifconfig wlan0 down 2>/dev/null
sleep 1
ifconfig wlan0 up
sleep 2
wpa_supplicant -B -D nl80211 -i wlan0 -c "$WPA" 2>&1 | tee -a "$LOG"
sleep 8
dhclient wlan0 2>&1 | tee -a "$LOG"
sleep 5

# --- 4. Resultado ----------------------------------------------------------
IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')
RED=$(iwgetid -r 2>/dev/null)

log "-----------------------------------------"
if [ -n "$IP" ]; then
    log "RESCATE CORRECTO"
    log "  red: ${RED:-desconocida}"
    log "  IP:  $IP"
    log "  Conectar con:  ssh pi@$IP"
else
    log "SIN IP - el rescate no logro conectar"
    log "  redes visibles:"
    iwlist wlan0 scan 2>/dev/null | grep -oE 'ESSID:"[^"]*"' | sort -u | head -15 | tee -a "$LOG"
    log "  Revisa que SSID y contrasena de wifi.txt sean correctos"
fi
log "  SSH activo: $(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null)"
log "===== RESCATE TERMINADO ====="
echo "" >> "$LOG"

exit 0
