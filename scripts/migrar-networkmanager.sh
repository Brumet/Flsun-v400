#!/usr/bin/env bash
#
# Migra la WiFi del Speeder Pad de wpa_supplicant+dhclient a NetworkManager
# sin perder la conexión por el camino.
#
# La wiki de Guilouz instala NetworkManager y luego reconecta a mano. Eso
# funciona si tienes cable Ethernet. Sin cable, NetworkManager reclama wlan0
# sin conocer la contraseña y te deja fuera del pad.
#
# Este script evita eso: lee la contraseña que ya está guardada en el propio
# pad, crea el perfil de NetworkManager ANTES de instalarlo, y verifica que
# haya IP al terminar. Si no la hay, restaura el estado anterior.
#
# Uso:  sudo bash migrar-networkmanager.sh
#
# Se relanza solo en segundo plano, así que sobrevive a una caída del SSH.

set -uo pipefail

LOG=/home/pi/migrar-nm.log
IFACE=wlan0
WPA=/etc/wpa_supplicant/wpa_supplicant.conf
ESPERA=90          # segundos que damos a NetworkManager para conseguir IP

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Hay que ejecutarlo con sudo."; exit 1; }

# Este script debe lanzarse con systemd-run, para que quede fuera de la sesión
# SSH y sobreviva al corte de red que provoca la propia migración:
#
#   sudo systemd-run --unit=migrar-nm bash /home/pi/migrar-networkmanager.sh
#
# Con "setsid + nohup" no basta: sudo ejecuta en un pty y, al cerrarse la
# sesión, se lleva por delante todo lo que cuelga de él.

exec >> "$LOG" 2>&1
echo "================ $(date) ================"

# ---------------------------------------------------------------- 1. estado
IP_ANTES=$(ip -4 -o addr show "$IFACE" | awk '{print $4}' | cut -d/ -f1)
echo "[1] IP actual en $IFACE: ${IP_ANTES:-ninguna}"

restaurar() {
    echo "[!] Restaurando la configuración anterior..."
    systemctl stop NetworkManager 2>/dev/null
    systemctl disable NetworkManager 2>/dev/null
    pkill -f "NetworkManager" 2>/dev/null
    ip addr flush dev "$IFACE" 2>/dev/null
    wpa_supplicant -B -D nl80211 -i "$IFACE" -c "$WPA"
    sleep 3
    dhclient "$IFACE"
    sleep 5
    echo "[!] IP tras restaurar: $(ip -4 -o addr show "$IFACE" | awk '{print $4}')"
}

# ------------------------------------------------- 2. credenciales del pad
# La contraseña sale del propio pad y no se muestra en ningún momento.
mapfile -t CREDS < <(python3 - "$WPA" <<'PY'
import re, sys
texto = open(sys.argv[1]).read()
for bloque in re.findall(r'network=\{(.*?)\}', texto, re.S):
    if re.search(r'^\s*disabled\s*=\s*1', bloque, re.M):
        continue                      # red desactivada, la saltamos
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
if [ -z "$SSID" ] || [ -z "$PSK" ]; then
    echo "[X] No pude extraer las credenciales de $WPA. No toco nada."
    exit 1
fi
echo "[2] Red encontrada: '$SSID' (contraseña leída del pad, no se muestra)"

# -------------------------------------------------- 3. perfil NetworkManager
mkdir -p /etc/NetworkManager/system-connections /etc/NetworkManager/conf.d
printf '[main]\nauth-polkit=false\n' > /etc/NetworkManager/conf.d/any-user.conf

UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
PERFIL="/etc/NetworkManager/system-connections/${SSID// /-}.nmconnection"
cat > "$PERFIL" <<PERF
[connection]
id=$SSID
uuid=$UUID
type=wifi
interface-name=$IFACE
autoconnect=true
autoconnect-priority=10

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$PSK

[ipv4]
method=auto

[ipv6]
method=auto
PERF
chown root:root "$PERFIL"
chmod 600 "$PERFIL"
echo "[3] Perfil creado en $PERFIL (permisos 600)"

# ------------------------------------------------------- 4. instalar paquete
echo "[4] Instalando network-manager..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y network-manager
echo "[4] apt terminó con código $? (un error de conexión abortada aquí es normal)"

if ! command -v nmcli >/dev/null 2>&1; then
    echo "[X] NetworkManager no se instaló. Restauro."
    restaurar
    exit 1
fi

# ------------------------------------------------------- 5. cambio de manos
echo "[5] Pasando $IFACE a NetworkManager..."
systemctl -q disable dhcpcd 2>/dev/null
systemctl -q stop dhcpcd 2>/dev/null
pkill -f "dhclient $IFACE" 2>/dev/null
pkill -f "wpa_supplicant -B -D nl80211 -i $IFACE" 2>/dev/null
systemctl enable NetworkManager
systemctl restart NetworkManager

# ------------------------------------------------------------ 6. verificar
echo "[6] Esperando IP (máximo ${ESPERA}s)..."
for i in $(seq 1 "$ESPERA"); do
    IP_AHORA=$(ip -4 -o addr show "$IFACE" | awk '{print $4}' | cut -d/ -f1)
    if [ -n "$IP_AHORA" ]; then
        echo "[OK] IP obtenida a los ${i}s: $IP_AHORA"
        nmcli -t -f DEVICE,STATE device 2>/dev/null
        echo "[OK] Migración completada. Ya puedes seguir con el instalador 2."
        exit 0
    fi
    sleep 1
done

echo "[X] Sin IP tras ${ESPERA}s."
restaurar
exit 1
