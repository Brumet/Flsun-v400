#!/bin/bash
# =============================================================================
#  FLSUN V400 / Speeder Pad  -  Conectar a una red WiFi nueva
#
#  Se ejecuta EN EL PAD, por SSH o desde una consola con teclado.
#  Detecta solo como esta gestionada la red y aplica la configuracion
#  por el metodo correcto. Hace copia de seguridad de todo lo que toca.
#
#  Uso:   sudo bash conectar-wifi.sh "NombreDeLaRed" "LaContrasena"
#  Ver:   sudo bash conectar-wifi.sh --diagnostico     (no cambia nada)
# =============================================================================

set -u
STAMP=$(date +%Y%m%d_%H%M%S)

c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_head() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

if [ "$(id -u)" != "0" ]; then
    c_err "Hay que ejecutarlo con sudo:"
    echo "  sudo bash $0 \"SSID\" \"password\""
    exit 1
fi

# --- Detectar la interfaz WiFi -----------------------------------------------
WIFI_IF=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(wlan|wlp|wlo)' | head -1)
[ -z "$WIFI_IF" ] && WIFI_IF="wlan0"

# --- Diagnostico -------------------------------------------------------------
diagnostico() {
    c_head "INTERFACES DE RED"
    ip -br link 2>/dev/null || ip link
    echo
    echo "Interfaz WiFi detectada: $WIFI_IF"

    c_head "SERVICIOS DE RED"
    for s in NetworkManager wpa_supplicant dhcpcd systemd-networkd; do
        printf '  %-20s %s\n' "$s" "$(systemctl is-active $s 2>/dev/null || echo no-instalado)"
    done

    c_head "ARCHIVOS DE CONFIGURACION"
    echo "-- /etc/netplan/"
    ls -la /etc/netplan/ 2>/dev/null || echo "   (no existe)"
    echo "-- /etc/wpa_supplicant/"
    ls -la /etc/wpa_supplicant/ 2>/dev/null || echo "   (no existe)"

    c_head "ESTADO ACTUAL"
    ip -br addr 2>/dev/null | grep -v '^lo'
    echo "Puerta de enlace: $(ip route | awk '/default/{print $3; exit}' || echo ninguna)"
}

if [ "${1:-}" = "--diagnostico" ] || [ "${1:-}" = "-d" ]; then
    diagnostico
    exit 0
fi

SSID="${1:-}"
PASS="${2:-}"
if [ -z "$SSID" ] || [ -z "$PASS" ]; then
    c_err "Faltan datos."
    echo "  sudo bash $0 \"NombreDeLaRed\" \"LaContrasena\""
    echo "  sudo bash $0 --diagnostico"
    exit 1
fi

diagnostico

# --- Elegir metodo -----------------------------------------------------------
USA_NM=$(systemctl is-active NetworkManager 2>/dev/null)
NETPLAN_FILE=$(ls /etc/netplan/*.yaml /etc/netplan/*.yml 2>/dev/null | head -1)
WPA_FILE=""
for f in /etc/wpa_supplicant/wpa_supplicant-${WIFI_IF}.conf /etc/wpa_supplicant/wpa_supplicant.conf; do
    [ -f "$f" ] && { WPA_FILE="$f"; break; }
done

c_head "APLICANDO CONFIGURACION"
echo "Red destino: $SSID"
echo "Interfaz   : $WIFI_IF"

# --- Metodo 1: NetworkManager ------------------------------------------------
if [ "$USA_NM" = "active" ]; then
    c_ok ">> Metodo: NetworkManager"
    nmcli device wifi rescan 2>/dev/null; sleep 3
    if nmcli device wifi connect "$SSID" password "$PASS" ifname "$WIFI_IF"; then
        c_ok "Conectado."
    else
        c_err "nmcli fallo. Revisa nombre y contrasena."
        exit 1
    fi

# --- Metodo 2: netplan -------------------------------------------------------
elif [ -n "$NETPLAN_FILE" ]; then
    c_ok ">> Metodo: netplan  ($NETPLAN_FILE)"
    cp -a "$NETPLAN_FILE" "${NETPLAN_FILE}.bak-${STAMP}"
    echo "   copia de seguridad: ${NETPLAN_FILE}.bak-${STAMP}"

    cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  wifis:
    ${WIFI_IF}:
      dhcp4: true
      optional: true
      access-points:
        "${SSID}":
          password: "${PASS}"
EOF
    chmod 600 "$NETPLAN_FILE"
    netplan generate && netplan apply || { c_err "netplan fallo. Restaurando."; cp -a "${NETPLAN_FILE}.bak-${STAMP}" "$NETPLAN_FILE"; netplan apply; exit 1; }

# --- Metodo 3: wpa_supplicant ------------------------------------------------
elif [ -n "$WPA_FILE" ]; then
    c_ok ">> Metodo: wpa_supplicant  ($WPA_FILE)"
    cp -a "$WPA_FILE" "${WPA_FILE}.bak-${STAMP}"
    echo "   copia de seguridad: ${WPA_FILE}.bak-${STAMP}"

    # Anadir la red sin borrar las existentes
    {
        echo ""
        echo "network={"
        echo "    ssid=\"${SSID}\""
        echo "    psk=\"${PASS}\""
        echo "    key_mgmt=WPA-PSK"
        echo "    priority=10"
        echo "}"
    } >> "$WPA_FILE"

    wpa_cli -i "$WIFI_IF" reconfigure 2>/dev/null || systemctl restart wpa_supplicant
    sleep 5
    dhclient -r "$WIFI_IF" 2>/dev/null
    dhclient "$WIFI_IF" 2>/dev/null &

else
    c_err "No se reconocio ningun metodo de gestion de red."
    echo "Manda la salida de:  sudo bash $0 --diagnostico"
    exit 1
fi

# --- Verificacion ------------------------------------------------------------
c_head "VERIFICANDO (hasta 40 s)"
IP=""
for i in $(seq 1 20); do
    IP=$(ip -4 addr show "$WIFI_IF" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    [ -n "$IP" ] && break
    printf '.'
    sleep 2
done
echo

if [ -n "$IP" ]; then
    c_ok "CONECTADO"
    echo
    echo "  IP del pad : $IP"
    echo "  Mainsail   : http://$IP"
    echo "  SSH        : ssh pi@$IP"
    echo
    if ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
        c_ok "  Salida a internet: OK"
    else
        c_warn "  Sin salida a internet (red local si funciona)"
    fi
    echo
    c_warn "APUNTA ESA IP. Es la direccion para entrar desde el navegador."
else
    c_err "NO se obtuvo IP."
    echo
    echo "Comprueba:"
    echo "  - Nombre de red exacto (mayusculas y minusculas cuentan)"
    echo "  - Contrasena correcta"
    echo "  - Que la red sea de 2,4 GHz (el pad puede no ver las de 5 GHz)"
    echo
    echo "Redes visibles ahora mismo:"
    iw dev "$WIFI_IF" scan 2>/dev/null | grep -E 'SSID:' | sed 's/^/   /' | sort -u | head -20
    exit 1
fi
