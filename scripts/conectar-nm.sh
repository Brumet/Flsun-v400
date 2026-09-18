#!/usr/bin/env bash
#
# Conecta wlan0 a NetworkManager reutilizando la contraseña que ya está
# guardada en wpa_supplicant.conf, y verifica que haya IP.
#
# Si NetworkManager no consigue conectar en 60 s, restaura el mecanismo
# original del pad (wpa_supplicant + dhclient lanzados por cfgguard.sh).
#
# Lanzar SIEMPRE con systemd-run, para que sobreviva al corte de SSH:
#   sudo systemd-run --unit=conectar-nm bash /home/pi/conectar-nm.sh

set -uo pipefail
LOG=/home/pi/conectar-nm.log
IFACE=wlan0
WPA=/etc/wpa_supplicant/wpa_supplicant.conf
ESPERA=60

exec >> "$LOG" 2>&1
echo "================ $(date) ================"

restaurar() {
    echo "[!] NetworkManager no conectó. Restaurando el método original."
    nmcli device disconnect "$IFACE" 2>/dev/null
    systemctl stop NetworkManager
    ip addr flush dev "$IFACE"
    ip link set "$IFACE" up
    wpa_supplicant -B -D nl80211 -i "$IFACE" -c "$WPA"
    sleep 3
    dhclient "$IFACE"
    sleep 5
    echo "[!] IP tras restaurar: $(ip -4 -o addr show "$IFACE" | awk '{print $4}')"
}

# --- credenciales, leídas del propio pad ---
mapfile -t CREDS < <(python3 - "$WPA" <<'PY'
import re, sys
texto = open(sys.argv[1]).read()
for bloque in re.findall(r'network=\{(.*?)\}', texto, re.S):
    if re.search(r'^\s*disabled\s*=\s*1', bloque, re.M):
        continue
    ssid = re.search(r'ssid="([^"]*)"', bloque)
    psk  = re.search(r'^\s*psk=(.+)$', bloque, re.M)
    if ssid and psk:
        print(ssid.group(1))
        print(psk.group(1).strip().strip('"'))
        break
PY
)
SSID="${CREDS[0]:-}"
PSK="${CREDS[1]:-}"
[ -n "$SSID" ] && [ -n "$PSK" ] || { echo "[X] No hay credenciales en $WPA. No toco nada."; exit 1; }
echo "[1] Red: '$SSID'"

# --- liberar wlan0 del mecanismo antiguo ---
echo "[2] Liberando $IFACE del wpa_supplicant antiguo..."
pkill -f "dhclient $IFACE" 2>/dev/null
pkill -f "wpa_supplicant -B -D nl80211 -i $IFACE" 2>/dev/null
sleep 2
systemctl restart NetworkManager
sleep 5

# --- conectar ---
echo "[3] Conectando con NetworkManager..."
nmcli device wifi rescan 2>/dev/null
sleep 3
nmcli device wifi connect "$SSID" password "$PSK" ifname "$IFACE"

# --- verificar ---
echo "[4] Esperando IP (máximo ${ESPERA}s)..."
for i in $(seq 1 "$ESPERA"); do
    IP=$(ip -4 -o addr show "$IFACE" | awk '{print $4}' | cut -d/ -f1)
    if [ -n "$IP" ]; then
        echo "[OK] IP $IP a los ${i}s"
        nmcli -t -f DEVICE,STATE,CONNECTION device | head -2
        exit 0
    fi
    sleep 1
done

restaurar
exit 1
