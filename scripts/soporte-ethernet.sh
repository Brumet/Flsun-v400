#!/bin/bash
# =============================================================================
#  Soporte para adaptador USB-Ethernet en el Speeder Pad
#
#  Deja el pad listo para que, al enchufar un adaptador USB-Ethernet, coja red
#  automaticamente. Sirve para:
#     - Conectarlo al router (mas estable que el WiFi para imprimir)
#     - Conectarlo DIRECTO AL PC, sin router, como via de rescate
#
#  NO TOCA wlan0. Solo configura las interfaces cableadas, que hoy no las
#  gestiona nadie: el netplan de fabrica declara eth0 pero systemd-networkd
#  esta en "enabled-runtime", asi que no sobrevive a un reinicio.
#
#  Esta es la via de entrada que falto el 2026-09-15, cuando el pad se quedo
#  sin red y hubo que reinstalar entero.
#
#  USO:  sudo bash soporte-ethernet.sh
# =============================================================================

set -u
LOG="/var/log/soporte-ethernet.log"

c_ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_head() { printf '\n\033[1;36m═══ %s ═══\033[0m\n' "$*" | tee -a "$LOG"; }
c_info() { printf '    %s\n' "$*" | tee -a "$LOG"; }

[ "$(id -u)" = "0" ] || { echo "Ejecutalo con: sudo bash $0"; exit 1; }

c_head "SOPORTE USB-ETHERNET"
echo "=== $(date) - soporte-ethernet ===" >> "$LOG"

IP_WIFI_ANTES=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}')
c_info "WiFi antes de empezar: ${IP_WIFI_ANTES:-sin IP}"

# --- Configuracion de red para interfaces cableadas ----------------------
# LinkLocalAddressing es la clave del caso "directo al PC": si no hay
# servidor DHCP al otro lado, la interfaz coge una 169.254.x.x y el pad sigue
# siendo alcanzable. Sin esto, un cable directo al portatil no da nada.
mkdir -p /etc/systemd/network

cat > /etc/systemd/network/10-cable.network <<'NETEOF'
# Interfaces cableadas del Speeder Pad (adaptadores USB-Ethernet incluidos).
# Creado por soporte-ethernet.sh - no gestiona wlan0 a proposito.

[Match]
Name=eth* en* usb*

[Network]
DHCP=ipv4
LinkLocalAddressing=ipv4
IPv6AcceptRA=no

[DHCP]
# Metrica alta: si hay WiFi y cable a la vez, manda el cable
RouteMetric=100
UseDomains=yes
NETEOF

c_ok "configuracion creada: /etc/systemd/network/10-cable.network"

# --- Hacer systemd-networkd persistente ----------------------------------
# Estaba en "enabled-runtime": activo ahora, pero no tras reiniciar.
ANTES=$(systemctl is-enabled systemd-networkd 2>&1)
systemctl enable systemd-networkd >>"$LOG" 2>&1
AHORA=$(systemctl is-enabled systemd-networkd 2>&1)
c_ok "systemd-networkd: $ANTES -> $AHORA"

systemctl restart systemd-networkd >>"$LOG" 2>&1
sleep 3
c_ok "systemd-networkd reiniciado"

# --- Comprobar que el WiFi sigue en pie ----------------------------------
IP_WIFI_AHORA=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}')
if [ -n "$IP_WIFI_AHORA" ]; then
    c_ok "WiFi intacto: $IP_WIFI_AHORA"
else
    c_warn "el WiFi perdio la IP - restaurando con el metodo del pad"
    wpa_supplicant -B -D nl80211 -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
    sleep 5
    dhclient wlan0 2>/dev/null
    sleep 3
    c_info "WiFi tras restaurar: $(ip -4 -o addr show wlan0 | awk '{print $4}')"
fi

# --- Estado de las interfaces cableadas ----------------------------------
c_head "INTERFACES CABLEADAS"
ENCONTRADA=0
for i in $(ls /sys/class/net/ 2>/dev/null); do
    case "$i" in
        eth*|en*|usb*)
            ENCONTRADA=1
            EST=$(cat "/sys/class/net/$i/operstate" 2>/dev/null)
            IP=$(ip -4 -o addr show "$i" 2>/dev/null | awk '{print $4}')
            c_info "$i: $EST ${IP:+- $IP}"
            ;;
    esac
done
[ "$ENCONTRADA" = "0" ] && c_info "ninguna (normal si el adaptador no esta enchufado)"

cat <<'FINEOF'

  COMO USARLO
  ───────────
  AL ROUTER:
     Enchufa el adaptador al pad y el cable al router. Coge IP sola.
     Mas estable que el WiFi para impresiones largas.

  DIRECTO AL PC (rescate, sin router):
     1. Adaptador al pad, cable al portatil
     2. En el portatil, comparte la conexion por ese puerto:
          Configuracion de red -> perfil cableado -> IPv4
          -> metodo "Compartido con otros equipos"
     3. Busca el pad:
          ping speeder-pad.local
          # o mira que IP reparte el portatil:
          ip neigh | grep -v FAILED

     Sin compartir la conexion tambien funciona: ambos cogen una direccion
     169.254.x.x y se ven entre si.

  COMPROBAR:
     ip -br addr          # interfaces y sus IPs
     networkctl status    # que ve systemd-networkd

FINEOF
exit 0
