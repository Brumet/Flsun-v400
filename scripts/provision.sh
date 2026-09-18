#!/bin/bash
# =============================================================================
#  FLSUN V400 / Speeder Pad  -  Aprovisionamiento automatico
#
#  Deja un pad recien restaurado de fabrica completamente operativo:
#  Klipper oficial, Moonraker, Mainsail, KlipperScreen de Guilouz con temas
#  propios y las configuraciones calibradas del repositorio.
#
#  PUNTO DE PARTIDA (obligatorio):
#    1. Imagen V1.2 restaurada por microSD (la V1.4 no permite SSH)
#    2. Tarjeta retirada y pad reiniciado
#    3. WiFi conectado DESDE LA PANTALLA TACTIL
#    4. Acceso por SSH funcionando
#
#  USO:
#    git clone https://github.com/Brumet/Flsun-v400.git
#    sudo bash Flsun-v400/scripts/provision.sh
#
#  Tarda entre 60 y 90 minutos, casi todo compilando en armhf. Es seguro
#  volver a ejecutarlo si algo falla a mitad.
#
#  NO TOCA LA RED. Es deliberado: instalar NetworkManager es lo que dejo un
#  pad incomunicado el 2026-09-15 y obligo a reinstalar. Ver AVISO CRITICO en
#  docs/RESTAURACION-PASO-A-PASO.md
# =============================================================================

set -u

PI_USER="pi"
PI_HOME="/home/pi"
DATA="$PI_HOME/printer_data"
LOG="/var/log/flsun-provision.log"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FALLOS=0

c_head() { printf '\n\033[1;36m═══ %s ═══\033[0m\n' "$*" | tee -a "$LOG"; }
c_ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" | tee -a "$LOG"; FALLOS=$((FALLOS+1)); }
c_info() { printf '    %s\n' "$*" | tee -a "$LOG"; }

como_pi() { sudo -u "$PI_USER" -H bash -c "$1"; }

# ---------------------------------------------------------------------------
#  Comprobaciones previas
# ---------------------------------------------------------------------------
c_head "COMPROBACIONES PREVIAS"

[ "$(id -u)" = "0" ] || { echo "Ejecutalo con: sudo bash $0"; exit 1; }
echo "=== Aprovisionamiento iniciado $(date) ===" >> "$LOG"

id "$PI_USER" >/dev/null 2>&1 || { c_err "No existe el usuario $PI_USER"; exit 1; }
c_ok "usuario $PI_USER"

if ! ping -c2 -W3 8.8.8.8 >/dev/null 2>&1; then
    c_err "Sin conexion a internet. Conecta el WiFi desde la pantalla antes de seguir."
    exit 1
fi
c_ok "internet"

getent hosts github.com >/dev/null 2>&1 && c_ok "DNS" || { c_err "DNS no resuelve"; exit 1; }

LIBRE=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
[ "${LIBRE:-0}" -ge 3 ] && c_ok "espacio libre: ${LIBRE}G" || { c_err "Espacio insuficiente (${LIBRE}G, hacen falta 3G)"; exit 1; }

[ -d "$REPO_DIR/config-pad" ] && c_ok "repositorio en $REPO_DIR" || { c_err "No encuentro config-pad/ - ejecuta el script desde el repositorio clonado"; exit 1; }

c_info "IP actual: $(hostname -I | awk '{print $1}')"
c_info "Registro completo en $LOG"

# ---------------------------------------------------------------------------
#  FASE 1  -  Retirar las builds de FLSUN
# ---------------------------------------------------------------------------
c_head "FASE 1/8 - Retirando las builds de FLSUN"

for n in 1 2 3; do
    for svc in "klipper-$n" "moonraker-$n"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
            rm -f "/etc/systemd/system/${svc}.service"
            c_ok "$svc eliminado"
        fi
    done
done

systemctl daemon-reload

# Los forks viejos: klipper de leexxiangyang, moonraker de zzcatvs
for d in klipper klippy-env moonraker moonraker-env; do
    if [ -d "$PI_HOME/$d" ]; then
        if [ "$d" = "klipper" ] && [ -d "$PI_HOME/$d/.git" ]; then
            VER=$(cd "$PI_HOME/$d" && git describe --tags 2>/dev/null)
            case "$VER" in
                v0.1[1-9].*|v0.[2-9]*) c_ok "klipper ya es oficial ($VER) - se conserva"; continue ;;
            esac
        fi
        rm -rf "${PI_HOME:?}/$d"
        c_ok "$d retirado"
    fi
done

[ -d "$PI_HOME/klipper_config" ] && c_ok "klipper_config antiguo conservado como referencia"

# ---------------------------------------------------------------------------
#  FASE 2  -  Paquetes del sistema
# ---------------------------------------------------------------------------
c_head "FASE 2/8 - Paquetes del sistema"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >>"$LOG" 2>&1 && c_ok "listas de paquetes" || c_warn "apt-get update dio avisos"

PAQUETES="git unzip dfu-util build-essential cmake libsystemd-dev python3-dev python3-venv
          libffi-dev libncurses-dev libusb-dev avrdude gcc-avr binutils-avr avr-libc
          pkg-config libjpeg-dev zlib1g-dev curl"

# IMPORTANTE: network-manager NO esta en la lista, y no debe estarlo.
if apt-get install -y -qq $PAQUETES >>"$LOG" 2>&1; then
    c_ok "paquetes instalados"
else
    c_warn "algun paquete no se instalo - revisa $LOG"
fi

# ---------------------------------------------------------------------------
#  FASE 3  -  Klipper oficial
# ---------------------------------------------------------------------------
c_head "FASE 3/8 - Klipper oficial (una sola instancia)"

if [ ! -d "$PI_HOME/klipper" ]; then
    como_pi "git clone -q https://github.com/Klipper3d/klipper.git $PI_HOME/klipper" \
        && c_ok "klipper clonado" || c_err "fallo al clonar klipper"
fi
KVER=$(como_pi "cd $PI_HOME/klipper && git describe --tags 2>/dev/null")
c_info "version: $KVER"

if [ ! -d "$PI_HOME/klippy-env" ]; then
    como_pi "python3 -m venv $PI_HOME/klippy-env" && c_ok "entorno virtual creado"
fi

c_info "instalando dependencias de Klipper (varios minutos)..."
como_pi "$PI_HOME/klippy-env/bin/pip -q install -U 'pip<25' setuptools wheel" >>"$LOG" 2>&1
if como_pi "$PI_HOME/klippy-env/bin/pip -q install -r $PI_HOME/klipper/scripts/klippy-requirements.txt" >>"$LOG" 2>&1; then
    c_ok "dependencias de Klipper"
else
    c_err "fallo instalando dependencias de Klipper"
fi

# Estructura printer_data (el layout moderno, no el klipper_config de FLSUN)
for sub in "" /config /logs /gcodes /comms /systemd /database; do
    como_pi "mkdir -p ${DATA}${sub}"
done
c_ok "estructura printer_data"

cat > "$DATA/systemd/klipper.env" <<ENVEOF
KLIPPER_ARGS="$PI_HOME/klipper/klippy/klippy.py $DATA/config/printer.cfg -I $DATA/comms/klippy.serial -l $DATA/logs/klippy.log -a $DATA/comms/klippy.sock"
ENVEOF
chown "$PI_USER:$PI_USER" "$DATA/systemd/klipper.env"

cat > /etc/systemd/system/klipper.service <<'SVCEOF'
[Unit]
Description=Klipper 3D Printer Firmware SV1
Documentation=https://www.klipper3d.org/
After=network-online.target
Wants=udev.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
User=pi
RemainAfterExit=no
WorkingDirectory=/home/pi/klipper
EnvironmentFile=/home/pi/printer_data/systemd/klipper.env
ExecStart=/home/pi/klippy-env/bin/python $KLIPPER_ARGS
Restart=always
RestartSec=10
SVCEOF

systemctl daemon-reload
systemctl enable klipper >>"$LOG" 2>&1
c_ok "servicio klipper creado y habilitado"

# ---------------------------------------------------------------------------
#  FASE 4  -  Moonraker  (aqui esta el arreglo clave)
# ---------------------------------------------------------------------------
c_head "FASE 4/8 - Moonraker"

if [ ! -d "$PI_HOME/moonraker" ]; then
    como_pi "git clone -q https://github.com/Arksine/moonraker.git $PI_HOME/moonraker" \
        && c_ok "moonraker clonado" || c_err "fallo al clonar moonraker"
fi

if [ ! -d "$PI_HOME/moonraker-env" ]; then
    como_pi "python3 -m venv $PI_HOME/moonraker-env" && c_ok "entorno virtual creado"
fi

# ---------------------------------------------------------------------------
#  EL ARREGLO QUE HACE QUE ESTO FUNCIONE EN UBUNTU 20.04
#
#  El pad trae Python 3.8.10 y pip 20.0.2. Moonraker moderno pide
#  zeroconf<=0.150.0, y esa version exige Python >=3.10. El requisito real es
#  zeroconf>=0.131.0, o sea que SI hay versiones validas para 3.8 - pero el
#  pip 20 usa el resolvedor antiguo, que no sabe retroceder y aborta con:
#
#     ERROR: Package 'zeroconf' requires a different Python: 3.8.10 not in '>=3.10'
#
#  Con pip 24 el resolvedor retrocede solo y elige zeroconf 0.136.2,
#  pillow 10.4.0 y tornado 6.4.2. pip<25 porque la 25 ya no soporta 3.8.
# ---------------------------------------------------------------------------
c_info "actualizando pip del entorno (evita el fallo de zeroconf)..."
if como_pi "$PI_HOME/moonraker-env/bin/pip -q install -U 'pip<25' setuptools wheel" >>"$LOG" 2>&1; then
    PIPV=$(como_pi "$PI_HOME/moonraker-env/bin/pip --version" | awk '{print $2}')
    c_ok "pip actualizado a $PIPV"
else
    c_err "no se pudo actualizar pip - Moonraker fallara"
fi

c_info "compilando dependencias de Moonraker (30-45 min: pillow y dbus-fast)..."
if como_pi "cd $PI_HOME/moonraker && $PI_HOME/moonraker-env/bin/pip install -r scripts/moonraker-requirements.txt" >>"$LOG" 2>&1; then
    c_ok "dependencias de Moonraker"
else
    c_err "fallo instalando dependencias de Moonraker - mira el final de $LOG"
fi

cat > "$DATA/systemd/moonraker.env" <<ENVEOF
MOONRAKER_ARGS="$PI_HOME/moonraker/moonraker/moonraker.py -d $DATA"
ENVEOF
chown "$PI_USER:$PI_USER" "$DATA/systemd/moonraker.env"

cat > /etc/systemd/system/moonraker.service <<'SVCEOF'
[Unit]
Description=API Server for Klipper SV1
Requires=network-online.target
After=network-online.target klipper.service

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
User=pi
RemainAfterExit=no
WorkingDirectory=/home/pi/moonraker
EnvironmentFile=/home/pi/printer_data/systemd/moonraker.env
ExecStart=/home/pi/moonraker-env/bin/python $MOONRAKER_ARGS
Restart=always
RestartSec=10
SVCEOF

groupadd -f moonraker-admin
systemctl daemon-reload
systemctl enable moonraker >>"$LOG" 2>&1
c_ok "servicio moonraker creado y habilitado"

# ---------------------------------------------------------------------------
#  FASE 5  -  Configuraciones calibradas
# ---------------------------------------------------------------------------
c_head "FASE 5/8 - Configuraciones calibradas"

for f in printer.cfg macros.cfg timelapse.cfg variables.cfg neopixels.cfg; do
    if [ -f "$REPO_DIR/config-pad/$f" ]; then
        cp "$REPO_DIR/config-pad/$f" "$DATA/config/$f"
        chown "$PI_USER:$PI_USER" "$DATA/config/$f"
        c_ok "$f"
    else
        c_warn "$f no esta en el repositorio"
    fi
done

# El MCU va por by-id: esa ruta no cambia aunque se mueva el cable de puerto,
# al contrario que las by-path que traen los perfiles de FLSUN.
MCU_ID=$(ls /dev/serial/by-id/ 2>/dev/null | grep -i "usb_serial\|1a86" | head -1)
if [ -n "$MCU_ID" ]; then
    c_ok "MCU detectado: $MCU_ID"
    sed -i "s|^serial:.*|serial: /dev/serial/by-id/$MCU_ID|" "$DATA/config/printer.cfg"
    c_ok "ruta del MCU fijada por by-id"
else
    c_warn "MCU no detectado - enciende la impresora y revisa el cable USB"
    c_warn "  luego: sed -i 's|^serial:.*|serial: /dev/serial/by-id/TU_ID|' $DATA/config/printer.cfg"
fi

# El acelerometro sin la placa puesta impide que Klipper arranque
sed -i 's|^\(\[include adxl.*\)|#\1|' "$DATA/config/printer.cfg"
c_ok "includes de ADXL comentados (evita que Klipper no arranque sin el KUSBA)"

# Moonraker minimo y correcto. Los update_manager de crowsnest, timelapse y
# KlipperScreen se anaden DESPUES de instalar cada componente, nunca antes.
if [ ! -f "$DATA/config/moonraker.conf" ]; then
    cat > "$DATA/config/moonraker.conf" <<'MRCONF'
[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: /home/pi/printer_data/comms/klippy.sock

[authorization]
trusted_clients:
    10.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    FE80::/10
    ::1/128
cors_domains:
    *.lan
    *.local
    *://localhost
    *://localhost:*
    *://my.mainsail.xyz
    *://app.fluidd.xyz

[octoprint_compat]
[history]

[machine]
shutdown_action: halt

[update_manager]
channel: dev
refresh_interval: 168

[update_manager mainsail]
type: web
channel: stable
repo: mainsail-crew/mainsail
path: /home/pi/mainsail
MRCONF
    chown "$PI_USER:$PI_USER" "$DATA/config/moonraker.conf"
    c_ok "moonraker.conf"
fi

systemctl restart klipper >>"$LOG" 2>&1
sleep 10
systemctl restart moonraker >>"$LOG" 2>&1
sleep 15

# ---------------------------------------------------------------------------
#  FASE 6  -  KlipperScreen de Guilouz
# ---------------------------------------------------------------------------
c_head "FASE 6/8 - KlipperScreen de Guilouz"

# No hace falta el instalador ni recrear el entorno: el servicio de fabrica
# apunta a una ruta fija, asi que basta con cambiar el directorio por debajo.
if [ -d "$PI_HOME/KlipperScreen/.git" ] && \
   como_pi "cd $PI_HOME/KlipperScreen && git remote -v" 2>/dev/null | grep -qi guilouz; then
    c_ok "KlipperScreen de Guilouz ya instalado"
else
    systemctl stop KlipperScreen 2>/dev/null
    rm -rf "$PI_HOME/KlipperScreen-guilouz"
    if como_pi "git clone -q --depth 1 https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git $PI_HOME/KlipperScreen-guilouz"; then
        [ -d "$PI_HOME/KlipperScreen" ] && mv "$PI_HOME/KlipperScreen" "$PI_HOME/KlipperScreen.fabrica"
        mv "$PI_HOME/KlipperScreen-guilouz" "$PI_HOME/KlipperScreen"
        c_ok "KlipperScreen sustituido (el de fabrica queda en KlipperScreen.fabrica)"
    else
        c_err "fallo al clonar KlipperScreen de Guilouz"
    fi
fi

# sdbus: sin esto el panel de red revienta con "No module named 'sdbus'"
if [ -d "$PI_HOME/.KlipperScreen-env" ]; then
    c_info "instalando sdbus (necesita libsystemd-dev, ya instalado)..."
    como_pi "$PI_HOME/.KlipperScreen-env/bin/pip -q install sdbus==0.11.1 sdbus_networkmanager==2.0.0" >>"$LOG" 2>&1
    if como_pi "$PI_HOME/.KlipperScreen-env/bin/python -c 'import sdbus'" 2>/dev/null; then
        c_ok "sdbus instalado"
    else
        c_warn "sdbus no entro - el panel de red de la pantalla no funcionara"
    fi
fi

# Temas propios. Cogen los iconos de material-blue, que el fork de fabrica no
# tiene: por eso solo funcionan sobre el de Guilouz.
for tema in cupertino cupertino-light; do
    if [ -d "$REPO_DIR/temas/$tema" ]; then
        cp -r "$REPO_DIR/temas/$tema" "$PI_HOME/KlipperScreen/styles/"
        [ -d "$PI_HOME/KlipperScreen/styles/material-blue/images" ] && \
            cp -r "$PI_HOME/KlipperScreen/styles/material-blue/images" "$PI_HOME/KlipperScreen/styles/$tema/"
        chown -R "$PI_USER:$PI_USER" "$PI_HOME/KlipperScreen/styles/$tema"
        echo "styles/$tema/" >> "$PI_HOME/KlipperScreen/.git/info/exclude"
        c_ok "tema $tema"
    fi
done

if [ -f "$REPO_DIR/config-pad/KlipperScreen.conf" ]; then
    cp "$REPO_DIR/config-pad/KlipperScreen.conf" "$DATA/config/"
    chown "$PI_USER:$PI_USER" "$DATA/config/KlipperScreen.conf"
    grep -q "^theme:" "$DATA/config/KlipperScreen.conf" || \
        sed -i "0,/^\[main\]/s//[main]\ntheme: cupertino/" "$DATA/config/KlipperScreen.conf"
    c_ok "KlipperScreen.conf con tema cupertino"
fi

# ---------------------------------------------------------------------------
#  FASE 7  -  API key  (el Unauthorized de la pantalla)
# ---------------------------------------------------------------------------
c_head "FASE 7/8 - Autorizacion de la pantalla"

# KlipperScreen manda una api_key VACIA, y Moonraker moderno interpreta la
# cadena vacia como intento fallido de autenticacion: revoca la confianza que
# le daba por venir de 127.0.0.1 y responde -32602 Unauthorized. Se arregla
# dandole la clave real. Cambia con cada instalacion limpia de Moonraker.
sleep 5
KEY=$(curl -s --max-time 10 http://127.0.0.1:7125/access/api_key | sed -E 's/.*"result":\s*"([^"]+)".*/\1/')
if [ ${#KEY} -gt 16 ] && [ -f "$DATA/config/KlipperScreen.conf" ]; then
    sed -i '/^moonraker_api_key:/d' "$DATA/config/KlipperScreen.conf"
    if grep -q "^\[printer " "$DATA/config/KlipperScreen.conf"; then
        sed -i "/^\[printer /a moonraker_api_key: $KEY" "$DATA/config/KlipperScreen.conf"
        c_ok "API key configurada (${KEY:0:8}...)"
    else
        c_warn "no hay seccion [printer ...] en KlipperScreen.conf"
    fi
else
    c_warn "no se pudo obtener la API key - la pantalla dara Unauthorized"
    c_warn "  arreglalo despues con: bash $REPO_DIR/scripts/fix-apikey.sh"
fi

systemctl restart KlipperScreen >>"$LOG" 2>&1

# Herramientas de red al alcance de la mano, en el propio pad
if [ -f "$REPO_DIR/scripts/conectar-wifi.sh" ]; then
    cp "$REPO_DIR/scripts/conectar-wifi.sh" "$PI_HOME/"
    chmod +x "$PI_HOME/conectar-wifi.sh"
    chown "$PI_USER:$PI_USER" "$PI_HOME/conectar-wifi.sh"
    c_ok "conectar-wifi.sh instalado en $PI_HOME"
fi

# ---------------------------------------------------------------------------
#  FASE 8  -  Verificacion
# ---------------------------------------------------------------------------
c_head "FASE 8/8 - Verificacion"

sleep 20
IP=$(hostname -I | awk '{print $1}')

for s in klipper moonraker KlipperScreen nginx; do
    EST=$(systemctl is-active "$s" 2>&1)
    [ "$EST" = "active" ] && c_ok "$s activo" || c_err "$s: $EST"
done

ESTADO=$(curl -s --max-time 10 http://127.0.0.1:7125/printer/info 2>/dev/null)
case "$ESTADO" in
    *'"state":"ready"'*|*'"state": "ready"'*)
        c_ok "IMPRESORA LISTA - Klipper conectado al MCU" ;;
    *"MCU Protocol error"*)
        c_err "Error de protocolo con el MCU"
        c_info "  El firmware de la placa no entiende a este Klipper."
        c_info "  Recompila y flashea: ver PASO 7 en docs/RESTAURACION-PASO-A-PASO.md"
        c_info "  (en las dos restauraciones de 2026-09-15 NO hizo falta)" ;;
    *"Unable to connect"*)
        c_err "Klipper no encuentra el MCU"
        c_info "  Enciende la impresora y revisa el cable USB. Luego:"
        c_info "  sudo systemctl restart klipper" ;;
    *)
        c_warn "Estado no concluyente. Revisa: $DATA/logs/klippy.log" ;;
esac

HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$IP/" 2>/dev/null)
[ "$HTTP" = "200" ] && c_ok "Mainsail responde en http://$IP" || c_warn "Mainsail devolvio HTTP $HTTP"

c_head "RESUMEN"
c_info "Klipper:    $(como_pi "cd $PI_HOME/klipper && git describe --tags 2>/dev/null")"
c_info "Mainsail:   http://$IP"
c_info "Registro:   $LOG"
echo ""

if [ "$FALLOS" -eq 0 ]; then
    printf '\033[1;32m  APROVISIONAMIENTO COMPLETADO SIN ERRORES\033[0m\n'
else
    printf '\033[1;31m  TERMINADO CON %s FALLO(S) - revisa lo marcado arriba\033[0m\n' "$FALLOS"
fi

cat <<'FINEOF'

  QUEDA POR HACER A MANO
  ──────────────────────
  1. CALIBRAR lo geometrico, en este orden:
        Z_OFFSET_CALIBRATION -> ENDSTOPS_CALIBRATION
        -> DELTA_CALIBRATION -> BED_LEVELING
     Los valores termicos y de extrusion del README siguen siendo validos.

  2. ZONA HORARIA (si no es Colombia):
        sudo timedatectl set-timezone America/Bogota

  3. CAMBIAR DE WIFI mas adelante:
        sudo bash /home/pi/conectar-wifi.sh "Red" "clave"
     NO instales NetworkManager sin un adaptador USB-Ethernet a mano.

  4. RESCATE: copia scripts/usb-rescate/update.sh a una memoria USB y
     guardala con el pad. Es la unica forma de entrar si se queda sin red.

  AVISOS
  ──────
  - Un 504 de nginx en calibraciones largas NO es un fallo: nginx corta a los
    10 minutos, Klipper sigue trabajando. Consulta el estado, no esperes.
  - Las macros no arrancan si idle_timeout esta en Printing. Espera a Ready.
  - Un z_offset que cambie mas de 0,5 mm sin tocar boquilla es un error de
    medida, no un dato. Repite antes de encadenar DELTA_CALIBRATION.

FINEOF

exit 0
