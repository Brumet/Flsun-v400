#!/bin/bash
# =============================================================================
#  Tailscale en el Speeder Pad  -  acceso remoto y SSH desde cualquier sitio
#
#  Crea una interfaz propia (tailscale0) y NO TOCA wlan0. No puede dejarte
#  fuera del pad como si hace NetworkManager: es seguro ejecutarlo por SSH.
#
#  Lo que aporta:
#    - Acceso a Mainsail y SSH sin estar en la red local ni abrir puertos
#    - Una direccion que NO CAMBIA NUNCA (el 2026-09-15 se perdio un pad
#      justamente porque cambio de IP)
#    - Nombre estable: "ssh flora" funciona desde cualquier parte
#
#  USO:
#    sudo bash tailscale-setup.sh flora
#    sudo bash tailscale-setup.sh v400-2
#    sudo bash tailscale-setup.sh sr-1
#
#  Al final imprime una URL: abrela en el navegador para autorizar la maquina
#  en tu cuenta de Tailscale. Sin ese paso no queda conectada.
# =============================================================================

set -u

NOMBRE="${1:-}"
LOG="/var/log/tailscale-setup.log"

c_ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_head() { printf '\n\033[1;36m═══ %s ═══\033[0m\n' "$*" | tee -a "$LOG"; }
c_info() { printf '    %s\n' "$*" | tee -a "$LOG"; }

[ "$(id -u)" = "0" ] || { echo "Ejecutalo con: sudo bash $0 NOMBRE"; exit 1; }

if [ -z "$NOMBRE" ]; then
    echo "Falta el nombre de la maquina."
    echo "  sudo bash $0 flora        # la V400 principal"
    echo "  sudo bash $0 v400-2       # la segunda V400"
    echo "  sudo bash $0 sr-1         # la FLSUN SR"
    exit 1
fi

# Tailscale solo admite letras, numeros y guiones en el nombre
case "$NOMBRE" in
    *[!a-z0-9-]*) c_err "Nombre invalido: solo minusculas, numeros y guiones"; exit 1 ;;
esac

c_head "TAILSCALE - configurando '$NOMBRE'"
echo "=== $(date) - tailscale-setup $NOMBRE ===" >> "$LOG"

# --- 1. Requisitos -------------------------------------------------------
IP_ANTES=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
c_info "IP local actual: ${IP_ANTES:-ninguna}"

if [ ! -c /dev/net/tun ]; then
    modprobe tun 2>/dev/null
    sleep 1
fi
if [ -c /dev/net/tun ]; then
    c_ok "/dev/net/tun disponible"
else
    c_err "Falta /dev/net/tun - este kernel no soporta Tailscale"
    c_info "Comprueba:  zgrep CONFIG_TUN /proc/config.gz"
    exit 1
fi

ping -c2 -W3 8.8.8.8 >/dev/null 2>&1 && c_ok "internet" || { c_err "Sin internet"; exit 1; }

# --- 2. Instalar ---------------------------------------------------------
if command -v tailscale >/dev/null 2>&1; then
    c_ok "tailscale ya instalado ($(tailscale version 2>/dev/null | head -1))"
else
    c_info "anadiendo el repositorio oficial..."
    CODENAME=$(lsb_release -cs 2>/dev/null || echo focal)
    mkdir -p /usr/share/keyrings

    if curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.noarmor.gpg" \
         -o /usr/share/keyrings/tailscale-archive-keyring.gpg 2>>"$LOG" &&
       curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.tailscale-keyring.list" \
         -o /etc/apt/sources.list.d/tailscale.list 2>>"$LOG"; then
        c_ok "repositorio anadido ($CODENAME)"
    else
        c_err "no se pudo anadir el repositorio de Tailscale"
        exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >>"$LOG" 2>&1
    if apt-get install -y -qq tailscale >>"$LOG" 2>&1; then
        c_ok "tailscale instalado: $(tailscale version 2>/dev/null | head -1)"
    else
        c_err "fallo al instalar tailscale - revisa $LOG"
        exit 1
    fi
fi

systemctl enable --now tailscaled >>"$LOG" 2>&1
sleep 3
[ "$(systemctl is-active tailscaled)" = "active" ] && c_ok "tailscaled activo" || c_err "tailscaled no arranca"

# --- 3. Nombre del sistema ----------------------------------------------
ACTUAL=$(hostname)
if [ "$ACTUAL" != "$NOMBRE" ]; then
    hostnamectl set-hostname "$NOMBRE" 2>>"$LOG"
    # Sin esto, cada sudo tarda porque no resuelve su propio nombre
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NOMBRE/" /etc/hosts
    else
        echo -e "127.0.1.1\t$NOMBRE" >> /etc/hosts
    fi
    c_ok "hostname: $ACTUAL -> $NOMBRE"
else
    c_ok "hostname ya era $NOMBRE"
fi

# --- 4. Conectar ---------------------------------------------------------
c_head "AUTORIZACION"

if tailscale status >/dev/null 2>&1 && ! tailscale status 2>&1 | grep -qi "logged out"; then
    c_ok "ya estaba conectado a tu red Tailscale"
    tailscale set --hostname="$NOMBRE" 2>/dev/null
    tailscale set --ssh 2>/dev/null && c_ok "SSH por Tailscale habilitado"
else
    c_info "Se va a abrir el registro. Copia la URL que aparezca y abrela"
    c_info "en el navegador para autorizar esta maquina."
    echo ""
    # --ssh permite entrar por SSH a traves de Tailscale, sin abrir puertos
    # --accept-dns=false: el pad resuelve DNS por su cuenta, no lo tocamos
    timeout 120 tailscale up --ssh --hostname="$NOMBRE" --accept-dns=false 2>&1 | tee -a "$LOG"
fi

# --- 5. Verificar --------------------------------------------------------
c_head "VERIFICACION"

sleep 5
IP_TS=$(tailscale ip -4 2>/dev/null | head -1)
IP_AHORA=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

if [ -n "$IP_TS" ]; then
    c_ok "IP de Tailscale: $IP_TS"
    c_ok "Nombre en la red: $NOMBRE"
    c_info ""
    c_info "Desde cualquier equipo con Tailscale:"
    c_info "    ssh pi@$NOMBRE"
    c_info "    http://$NOMBRE          (Mainsail)"
    c_info "    http://$IP_TS"
else
    c_warn "Sin IP de Tailscale todavia"
    c_warn "Falta autorizar la maquina. Ejecuta y abre la URL que salga:"
    c_warn "    sudo tailscale up --ssh --hostname=$NOMBRE"
fi

# Lo importante: comprobar que no hemos roto la red local
if [ "$IP_AHORA" = "$IP_ANTES" ] && [ -n "$IP_AHORA" ]; then
    c_ok "red local intacta ($IP_AHORA)"
elif [ -n "$IP_AHORA" ]; then
    c_warn "la IP local cambio: $IP_ANTES -> $IP_AHORA (no es grave)"
else
    c_err "SE PERDIO LA IP LOCAL - restaurando"
    wpa_supplicant -B -D nl80211 -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
    sleep 5
    dhclient wlan0 2>/dev/null
fi

c_info ""
c_info "Estado en cualquier momento:  tailscale status"
c_info "Registro:                     $LOG"
exit 0
