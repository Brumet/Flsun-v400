#!/bin/bash
# =============================================================================
#  Activar / desactivar el acelerometro KUSBA (input shaper)
#
#  El [include adxlmcu.cfg] solo puede estar activo con la placa conectada:
#  si se deja puesto sin el KUSBA, KLIPPER NO ARRANCA y la impresora queda
#  inutilizable hasta editar el fichero a mano. Ya paso una vez.
#
#  Este script lo evita: comprueba que la placa este presente antes de
#  activar, y si Klipper no levanta, DESHACE EL CAMBIO SOLO.
#
#  USO:
#    bash activar-acelerometro.sh on       # antes de medir resonancias
#    bash activar-acelerometro.sh off      # al terminar, con el sensor fuera
#    bash activar-acelerometro.sh estado
# =============================================================================

set -u

ACCION="${1:-estado}"
CFG="/home/pi/printer_data/config/printer.cfg"
INC="adxlmcu.cfg"
API="http://127.0.0.1:7125"

c_ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; }
c_info() { printf '    %s\n' "$*"; }

[ -f "$CFG" ] || { c_err "No encuentro $CFG"; exit 1; }

detectar_kusba() {
    ls /dev/serial/by-id/ 2>/dev/null | grep -iE "rampon|anchor|kusba" | head -1
}

estado_klipper() {
    curl -s --max-time 8 "$API/printer/info" 2>/dev/null
}

esperar_klipper() {
    for _ in $(seq 1 12); do
        sleep 5
        EST=$(estado_klipper)
        case "$EST" in
            *'"state":"ready"'*|*'"state": "ready"'*) echo "ready"; return 0 ;;
            *'"state":"error"'*|*'"state": "error"'*) echo "error"; return 1 ;;
        esac
    done
    echo "timeout"; return 1
}

# ---------------------------------------------------------------- ESTADO ---
if [ "$ACCION" = "estado" ]; then
    printf '\n\033[1;36m═══ ACELEROMETRO ═══\033[0m\n'
    KUSBA=$(detectar_kusba)
    [ -n "$KUSBA" ] && c_ok "placa conectada: $KUSBA" || c_info "placa NO conectada"

    if grep -qE "^\s*\[include $INC\]" "$CFG"; then
        c_ok "include ACTIVO en printer.cfg"
    elif grep -qE "^\s*#\s*\[include $INC\]" "$CFG"; then
        c_info "include comentado (desactivado)"
    else
        c_info "no hay include de $INC en printer.cfg"
    fi

    EST=$(estado_klipper)
    case "$EST" in
        *'"state":"ready"'*|*'"state": "ready"'*) c_ok "Klipper listo" ;;
        *) c_warn "Klipper no esta listo" ;;
    esac
    echo ""
    exit 0
fi

# ------------------------------------------------------------------- OFF ---
if [ "$ACCION" = "off" ]; then
    printf '\n\033[1;36m═══ DESACTIVANDO ACELEROMETRO ═══\033[0m\n'
    if grep -qE "^\s*\[include $INC\]" "$CFG"; then
        cp "$CFG" "${CFG}.bak_$(date +%Y%m%d_%H%M%S)"
        sed -i "s|^\s*\(\[include $INC\]\)|#\1|" "$CFG"
        c_ok "include comentado"
        sudo systemctl restart klipper
        RES=$(esperar_klipper)
        [ "$RES" = "ready" ] && c_ok "Klipper listo" || c_warn "Klipper: $RES"
    else
        c_ok "ya estaba desactivado"
    fi
    echo ""
    exit 0
fi

# -------------------------------------------------------------------- ON ---
if [ "$ACCION" != "on" ]; then
    echo "Uso: bash $0 [on|off|estado]"
    exit 1
fi

printf '\n\033[1;36m═══ ACTIVANDO ACELEROMETRO ═══\033[0m\n'

# 1. La placa tiene que estar presente. Sin esto, Klipper no arranca.
KUSBA=$(detectar_kusba)
if [ -z "$KUSBA" ]; then
    c_err "El KUSBA no esta conectado"
    c_info "Conectalo por USB y vuelve a intentarlo. Puertos disponibles:"
    ls /dev/serial/by-id/ 2>/dev/null | sed 's/^/      /' || c_info "      (ninguno)"
    c_info ""
    c_info "No activo el include: Klipper no arrancaria."
    exit 1
fi
c_ok "placa detectada: $KUSBA"

# 2. Si la ruta real no coincide con la del cfg, ajustarla
ADXLCFG="/home/pi/printer_data/config/$INC"
if [ -f "$ADXLCFG" ]; then
    ESPERADA=$(grep -E "^serial:" "$ADXLCFG" | awk '{print $2}')
    REAL="/dev/serial/by-id/$KUSBA"
    if [ "$ESPERADA" != "$REAL" ]; then
        c_warn "la ruta del cfg no coincide con la real, la ajusto"
        c_info "  cfg:  $ESPERADA"
        c_info "  real: $REAL"
        sed -i "s|^serial:.*|serial: $REAL|" "$ADXLCFG"
        c_ok "ruta actualizada"
    fi
else
    c_err "Falta $ADXLCFG - copialo desde config-pad/ del repositorio"
    exit 1
fi

# 3. Activar el include (o anadirlo si no existe)
cp "$CFG" "${CFG}.bak_$(date +%Y%m%d_%H%M%S)"
if grep -qE "^\s*#\s*\[include $INC\]" "$CFG"; then
    sed -i "s|^\s*#\s*\(\[include $INC\]\)|\1|" "$CFG"
    c_ok "include descomentado"
elif grep -qE "^\s*\[include $INC\]" "$CFG"; then
    c_ok "include ya estaba activo"
else
    sed -i "0,/^\[include macros.cfg\]/s||[include $INC]\n[include macros.cfg]|" "$CFG"
    grep -qE "^\s*\[include $INC\]" "$CFG" && c_ok "include anadido" || \
        { echo "[include $INC]" >> "$CFG"; c_ok "include anadido al final"; }
fi

# 4. Reiniciar y comprobar - con marcha atras si no arranca
c_info "reiniciando Klipper..."
sudo systemctl restart klipper
RES=$(esperar_klipper)

if [ "$RES" = "ready" ]; then
    c_ok "KLIPPER LISTO CON EL ACELEROMETRO"
    c_info ""
    c_info "Antes de medir, una lectura de descarte (la primera del ADXL"
    c_info "siempre sale invalida, es por diseño):"
    c_info "    ACCELEROMETER_QUERY"
    c_info ""
    c_info "Y luego:"
    c_info "    SHAPER_CALIBRATE AXIS=X"
    c_info "    SHAPER_CALIBRATE AXIS=Y"
    c_info ""
    c_info "Un 504 de nginx en mitad de la medida NO es un fallo: nginx corta"
    c_info "a los 10 minutos y Klipper sigue trabajando."
    c_info ""
    c_info "Al terminar:  bash $0 off"
else
    c_err "Klipper no arranco ($RES) - DESHACIENDO"
    sed -i "s|^\s*\(\[include $INC\]\)|#\1|" "$CFG"
    sudo systemctl restart klipper
    RES2=$(esperar_klipper)
    if [ "$RES2" = "ready" ]; then
        c_ok "revertido: Klipper vuelve a estar listo"
    else
        c_err "Klipper sigue sin arrancar. Mira el log:"
        c_info "  tail -40 /home/pi/printer_data/logs/klippy.log"
    fi
    exit 1
fi
echo ""
exit 0
