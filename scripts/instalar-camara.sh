#!/bin/bash
# =============================================================================
#  Camara (Crowsnest) y timelapse para el Speeder Pad
#
#  Instala Crowsnest para servir la webcam en /webcam/ y el componente
#  moonraker-timelapse, que es el que falta cuando timelapse.cfg esta puesto
#  pero no graba nada: las macros viven en Klipper, la grabacion la hace un
#  componente de Moonraker que hay que instalar aparte.
#
#  Incluye el arreglo del arranque: Crowsnest arranca antes de que el USB de
#  la camara termine de enumerarse y muere con
#      ERROR: Start of ustreamer failed
#  dejando /webcam/ en HTTP 502 aunque systemctl diga "active". Se corrige con
#  un retardo de 15 s en el servicio.
#
#  USO:  sudo bash instalar-camara.sh
# =============================================================================

set -u

PI_USER="pi"
PI_HOME="/home/pi"
DATA="$PI_HOME/printer_data"
LOG="/var/log/instalar-camara.log"

c_ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_head() { printf '\n\033[1;36m═══ %s ═══\033[0m\n' "$*" | tee -a "$LOG"; }
c_info() { printf '    %s\n' "$*" | tee -a "$LOG"; }
como_pi() { sudo -u "$PI_USER" -H bash -c "$1"; }

[ "$(id -u)" = "0" ] || { echo "Ejecutalo con: sudo bash $0"; exit 1; }
echo "=== $(date) - instalar-camara ===" >> "$LOG"

# --------------------------------------------------------------- CAMARA ---
c_head "1/4 - Buscando la camara"

VIDEO=""
for v in /dev/video*; do
    [ -e "$v" ] || continue
    if v4l2-ctl --device="$v" --all 2>/dev/null | grep -qi "Video Capture"; then
        VIDEO="$v"; break
    fi
    [ -z "$VIDEO" ] && VIDEO="$v"
done

if [ -n "$VIDEO" ]; then
    c_ok "camara en $VIDEO"
    NOMBRE=$(v4l2-ctl --device="$VIDEO" --info 2>/dev/null | grep -i "Card type" | cut -d: -f2- | xargs)
    [ -n "$NOMBRE" ] && c_info "modelo: $NOMBRE"
else
    c_warn "no veo ninguna camara conectada"
    c_info "Puedes seguir: la configuracion queda lista para cuando la enchufes."
fi

# ------------------------------------------------------------ CROWSNEST ---
c_head "2/4 - Crowsnest"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq v4l-utils >>"$LOG" 2>&1

if [ -d "$PI_HOME/crowsnest" ]; then
    c_ok "crowsnest ya clonado"
else
    como_pi "git clone -q https://github.com/mainsail-crew/crowsnest.git $PI_HOME/crowsnest" \
        && c_ok "crowsnest clonado" || { c_err "fallo al clonar crowsnest"; exit 1; }
fi

if systemctl list-unit-files 2>/dev/null | grep -q "^crowsnest.service"; then
    c_ok "servicio crowsnest ya existe"
else
    c_info "instalando (unos minutos)..."
    cd "$PI_HOME/crowsnest" || exit 1
    if CROWSNEST_UNATTENDED=1 make install BASE_USER="$PI_USER" >>"$LOG" 2>&1; then
        c_ok "crowsnest instalado"
    else
        c_err "el instalador de crowsnest fallo - revisa $LOG"
        c_info "Prueba a mano:  cd ~/crowsnest && sudo make install"
        exit 1
    fi
fi

# ----------------------------------------------------------------- CONF ---
c_head "3/4 - Configuracion"

CONF="$DATA/config/crowsnest.conf"
if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<CNEOF
[crowsnest]
log_path: $DATA/logs/crowsnest.log
log_level: verbose
delete_log: false
no_proxy: false

[cam 1]
mode: ustreamer
enable_rtsp: false
rtsp_port: 8554
port: 8080
device: ${VIDEO:-/dev/video0}
resolution: 1280x720
max_fps: 15
custom_flags:
v4l2ctl:
CNEOF
    chown "$PI_USER:$PI_USER" "$CONF"
    c_ok "crowsnest.conf creado (${VIDEO:-/dev/video0}, 1280x720, 15 fps)"
else
    c_ok "crowsnest.conf ya existe - no lo toco"
fi

# EL ARREGLO: sin este retardo, crowsnest arranca antes de que el USB de la
# camara este listo y muere. systemctl dice "active" pero /webcam/ da 502.
mkdir -p /etc/systemd/system/crowsnest.service.d
cat > /etc/systemd/system/crowsnest.service.d/override.conf <<'OVEOF'
# Crowsnest arranca antes de que el USB de la camara termine de enumerarse y
# muere con "ERROR: Start of ustreamer failed". El retardo lo evita.
[Unit]
StartLimitIntervalSec=0

[Service]
ExecStartPre=/bin/sleep 15
Restart=on-failure
RestartSec=10
OVEOF
c_ok "retardo de arranque aplicado (15 s)"
systemctl daemon-reload

# ------------------------------------------------------------ TIMELAPSE ---
c_head "4/4 - Timelapse"

# printer.cfg incluye timelapse.cfg, pero eso solo trae las macros. La
# grabacion la hace este componente de Moonraker, que va aparte.
if [ -f "$PI_HOME/moonraker/moonraker/components/timelapse.py" ]; then
    c_ok "componente timelapse ya instalado"
else
    if [ ! -d "$PI_HOME/moonraker-timelapse" ]; then
        como_pi "git clone -q https://github.com/mainsail-crew/moonraker-timelapse.git $PI_HOME/moonraker-timelapse" \
            || c_err "fallo al clonar moonraker-timelapse"
    fi
    if [ -d "$PI_HOME/moonraker-timelapse" ]; then
        cd "$PI_HOME/moonraker-timelapse" || exit 1
        if make install >>"$LOG" 2>&1; then
            c_ok "componente timelapse instalado"
        else
            # A mano: es un solo fichero
            cp component/timelapse.py "$PI_HOME/moonraker/moonraker/components/" 2>/dev/null \
                && { chown "$PI_USER:$PI_USER" "$PI_HOME/moonraker/moonraker/components/timelapse.py"; c_ok "componente copiado a mano"; } \
                || c_err "no se pudo instalar el componente"
        fi
    fi
fi

# --- moonraker.conf: las entradas que faltaban --------------------------
MRCONF="$DATA/config/moonraker.conf"
if [ -f "$MRCONF" ]; then
    cp "$MRCONF" "${MRCONF}.bak_$(date +%Y%m%d_%H%M%S)"

    grep -q "^\[timelapse\]" "$MRCONF" || cat >> "$MRCONF" <<'TLEOF'

[timelapse]
output_path: /home/pi/printer_data/timelapse/
frame_path: /tmp/timelapse/
ffmpeg_binary_path: /usr/bin/ffmpeg
TLEOF

    # Los update_manager se anaden AHORA, con los componentes ya instalados.
    # Ponerlos antes es lo que llena Moonraker de errores.
    grep -q "update_manager crowsnest" "$MRCONF" || cat >> "$MRCONF" <<'UMEOF'

[update_manager crowsnest]
type: git_repo
path: /home/pi/crowsnest
origin: https://github.com/mainsail-crew/crowsnest.git
managed_services: crowsnest
install_script: tools/pkglist.sh
UMEOF

    grep -q "update_manager timelapse" "$MRCONF" || cat >> "$MRCONF" <<'UMEOF'

[update_manager timelapse]
type: git_repo
primary_branch: main
path: /home/pi/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: klipper moonraker
UMEOF

    chown "$PI_USER:$PI_USER" "$MRCONF"
    c_ok "moonraker.conf actualizado"
fi

como_pi "mkdir -p $DATA/timelapse"
apt-get install -y -qq ffmpeg >>"$LOG" 2>&1 && c_ok "ffmpeg" || c_warn "ffmpeg no se instalo"

# ---------------------------------------------------------- VERIFICAR ----
c_head "VERIFICACION"

systemctl enable crowsnest >>"$LOG" 2>&1
systemctl restart crowsnest >>"$LOG" 2>&1
systemctl restart moonraker >>"$LOG" 2>&1
c_info "esperando al retardo de arranque (15 s) y a Moonraker..."
sleep 30

EST=$(systemctl is-active crowsnest 2>&1)
[ "$EST" = "active" ] && c_ok "crowsnest activo" || c_err "crowsnest: $EST"
[ "$(systemctl is-active moonraker)" = "active" ] && c_ok "moonraker activo" || c_err "moonraker caido"

IP=$(hostname -I | awk '{print $1}')
# OJO: pgrep ustreamer devuelve 0 aunque funcione, porque corre como
# ustreamer.bin. Hay que comprobar por la URL, nunca con pgrep.
HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "http://127.0.0.1/webcam/?action=snapshot" 2>/dev/null)
case "$HTTP" in
    200) c_ok "LA CAMARA FUNCIONA - http://$IP/webcam/?action=snapshot" ;;
    502) c_err "HTTP 502 - ustreamer no arranco"
         c_info "  Revisa:  tail -30 $DATA/logs/crowsnest.log"
         c_info "  Suele ser el device: comprueba que ${VIDEO:-/dev/video0} exista" ;;
    404) c_warn "HTTP 404 - nginx no tiene la ruta /webcam/"
         c_info "  Revisa la configuracion de nginx del pad" ;;
    *)   c_warn "HTTP $HTTP - sin camara conectada, es lo esperado" ;;
esac

c_info ""
c_info "Timelapse: se activa desde Mainsail, pestaña Timelapse."
c_info "Los videos quedan en $DATA/timelapse/"
c_info "Registro: $LOG"
exit 0
