#!/bin/bash
# =============================================================================
#  FLSUN V400 / Speeder Pad  -  Preparar el portatil para el trabajo en sitio
#
#  Se ejecuta EN EL PORTATIL, en casa, ANTES de salir. Deja todo listo para
#  que en casa del cliente no haya que instalar ni descargar nada.
#
#  Hace:  dependencias (git, ssh, scp, curl, python3)  ->  paramiko  ->
#         repositorio clonado/actualizado  ->  permisos de ejecucion  ->
#         verificacion final de todo.
#
#  Uso:   bash preparar-portatil.sh
#         bash preparar-portatil.sh --verificar          (no cambia nada)
#         bash preparar-portatil.sh --dir ~/otra/ruta
#         bash preparar-portatil.sh --pad 192.168.1.50   (prueba alcanzar el pad)
# =============================================================================

set -u

REPO_URL="https://github.com/Brumet/Flsun-v400.git"
REPO_DIR="$HOME/Flsun-v400"
PAD_HOST=""
SOLO_VERIFICAR=0
FALLOS=0
AVISOS=0

c_ok()   { printf '\033[1;32m  OK  \033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m AVISO\033[0m %s\n' "$*"; AVISOS=$((AVISOS+1)); }
c_err()  { printf '\033[1;31m FALLO\033[0m %s\n' "$*"; FALLOS=$((FALLOS+1)); }
c_info() { printf '        %s\n' "$*"; }
c_head() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

ayuda() {
    cat <<'FIN'
Preparar el portatil para el trabajo en sitio (FLSUN V400 / Speeder Pad).

Se ejecuta EN EL PORTATIL, en casa, ANTES de salir. Instala las dependencias,
instala paramiko, clona o actualiza el repositorio, da permisos de ejecucion a
los scripts y lo verifica todo.

  bash preparar-portatil.sh                     prepara y verifica
  bash preparar-portatil.sh --verificar         solo mira, no cambia nada
  bash preparar-portatil.sh --dir ~/otra/ruta   donde clonar el repositorio
  bash preparar-portatil.sh --pad 192.168.1.50  prueba si se alcanza el pad

Devuelve 0 si todo esta correcto, 1 si queda algun fallo por resolver.
FIN
    exit 0
}

exige_valor() {
    [ -n "${2:-}" ] || { c_err "la opcion $1 necesita un valor"; exit 1; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        --verificar|-v) SOLO_VERIFICAR=1; shift ;;
        --dir)          exige_valor --dir "${2:-}"; REPO_DIR="$2"; shift 2 ;;
        --pad)          exige_valor --pad "${2:-}"; PAD_HOST="$2"; shift 2 ;;
        --ayuda|-h|--help) ayuda ;;
        *) c_err "Opcion desconocida: $1"; echo "Prueba: bash $0 --ayuda"; exit 1 ;;
    esac
done

if [ "$(id -u)" = "0" ]; then
    c_err "No lo ejecutes con sudo. Es para tu usuario normal."
    c_info "El script pedira la contrasena solo cuando necesite instalar paquetes."
    exit 1
fi

# --- Si ya estamos dentro del repositorio, trabajamos sobre ese ---------------
if RAIZ=$(git rev-parse --show-toplevel 2>/dev/null); then
    if [ -f "$RAIZ/scripts/conectar-wifi.sh" ]; then
        REPO_DIR="$RAIZ"
    fi
fi

# --- Instalador de paquetes del sistema --------------------------------------
APT_ACTUALIZADO=0
instalar_apt() {
    local paquete="$1"
    if [ "$SOLO_VERIFICAR" = "1" ]; then
        c_warn "falta '$paquete' (modo --verificar: no se instala)"
        return 1
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        c_err "falta '$paquete' y este sistema no usa apt. Instalalo a mano."
        return 1
    fi
    if [ "$APT_ACTUALIZADO" = "0" ]; then
        c_info "Actualizando indice de paquetes..."
        sudo apt-get update -qq || true
        APT_ACTUALIZADO=1
    fi
    c_info "Instalando $paquete..."
    sudo apt-get install -y -qq "$paquete" >/dev/null 2>&1
}

# =============================================================================
c_head "1. HERRAMIENTAS BASICAS"
# =============================================================================
#  comando : paquete apt
for par in "git:git" "ssh:openssh-client" "scp:openssh-client" \
           "curl:curl" "python3:python3" "ping:iputils-ping"; do
    cmd="${par%%:*}"; pkg="${par##*:}"
    if command -v "$cmd" >/dev/null 2>&1; then
        c_ok "$cmd"
    else
        instalar_apt "$pkg"
        if command -v "$cmd" >/dev/null 2>&1; then
            c_ok "$cmd (recien instalado)"
        else
            c_err "$cmd no disponible"
        fi
    fi
done

# =============================================================================
c_head "2. PARAMIKO"
# =============================================================================
tiene_paramiko() { python3 -c 'import paramiko' >/dev/null 2>&1; }

if tiene_paramiko; then
    c_ok "paramiko $(python3 -c 'import paramiko; print(paramiko.__version__)' 2>/dev/null)"
elif [ "$SOLO_VERIFICAR" = "1" ]; then
    c_warn "paramiko no esta instalado (modo --verificar: no se instala)"
else
    # El orden importa: el paquete de la distribucion es el que menos problemas
    # da. pip sin venv falla en Ubuntu 23.04+ y Debian 12+ (PEP 668).
    c_info "Intento 1 de 3: paquete del sistema (python3-paramiko)"
    instalar_apt python3-paramiko

    if ! tiene_paramiko; then
        c_info "Intento 2 de 3: pip --user"
        command -v pip3 >/dev/null 2>&1 || instalar_apt python3-pip
        python3 -m pip install --user -q paramiko >/dev/null 2>&1 || \
        python3 -m pip install --user -q --break-system-packages paramiko >/dev/null 2>&1 || true
    fi

    if ! tiene_paramiko; then
        c_info "Intento 3 de 3: entorno virtual en ~/.venv-flsun"
        instalar_apt python3-venv
        python3 -m venv "$HOME/.venv-flsun" >/dev/null 2>&1 && \
        "$HOME/.venv-flsun/bin/pip" install -q paramiko >/dev/null 2>&1
        if "$HOME/.venv-flsun/bin/python" -c 'import paramiko' >/dev/null 2>&1; then
            c_ok "paramiko instalado en ~/.venv-flsun"
            c_warn "para usarlo hay que activarlo antes:"
            c_info "  source ~/.venv-flsun/bin/activate"
        else
            c_err "no se ha podido instalar paramiko por ningun metodo"
        fi
    else
        c_ok "paramiko $(python3 -c 'import paramiko; print(paramiko.__version__)' 2>/dev/null)"
    fi
fi

# =============================================================================
c_head "3. REPOSITORIO"
# =============================================================================
if [ -d "$REPO_DIR/.git" ]; then
    c_ok "clonado en $REPO_DIR"
    if [ "$SOLO_VERIFICAR" = "0" ]; then
        c_info "Actualizando desde origin..."
        if git -C "$REPO_DIR" pull --ff-only >/dev/null 2>&1; then
            c_ok "al dia ($(git -C "$REPO_DIR" log -1 --format=%h\ %s))"
        else
            c_warn "no se ha podido actualizar (sin red, o hay cambios locales)"
            c_info "Se usara la copia que ya tienes: $(git -C "$REPO_DIR" log -1 --format=%h\ %s 2>/dev/null)"
        fi
    fi
elif [ "$SOLO_VERIFICAR" = "1" ]; then
    c_err "no hay repositorio en $REPO_DIR"
else
    c_info "Clonando en $REPO_DIR..."
    if git clone -q "$REPO_URL" "$REPO_DIR"; then
        c_ok "clonado en $REPO_DIR"
    else
        c_err "no se ha podido clonar $REPO_URL"
    fi
fi

# =============================================================================
c_head "4. PERMISOS DE EJECUCION"
# =============================================================================
if [ -d "$REPO_DIR/scripts" ]; then
    for s in "$REPO_DIR"/scripts/*.sh; do
        [ -e "$s" ] || continue
        if [ "$SOLO_VERIFICAR" = "0" ]; then
            chmod +x "$s" 2>/dev/null
        fi
        if [ -x "$s" ]; then
            c_ok "$(basename "$s")"
        else
            c_warn "$(basename "$s") sin permiso de ejecucion"
            c_info "  (da igual si lo lanzas con 'bash $(basename "$s")')"
        fi
    done
else
    c_err "no existe $REPO_DIR/scripts"
fi

# =============================================================================
c_head "5. FICHEROS QUE HARAN FALTA ALLI"
# =============================================================================
for f in scripts/conectar-wifi.sh docs/RUNBOOK-EN-SITIO.md docs/INSTRUCCIONES.md \
         config-pad/printer.cfg config-pad/moonraker.conf; do
    if [ -f "$REPO_DIR/$f" ]; then
        c_ok "$f"
    else
        c_err "falta $f"
    fi
done

# =============================================================================
c_head "6. DATOS DE ESTE PORTATIL"
# =============================================================================
printf '  usuario : %s\n' "$(whoami)"
printf '  equipo  : %s\n' "$(hostname)"
printf '  IPs     : %s\n' "$(hostname -I 2>/dev/null || echo desconocidas)"
printf '  ssh     : %s\n' "$(systemctl is-active ssh 2>/dev/null \
                             || systemctl is-active sshd 2>/dev/null \
                             || echo no-instalado)"

# =============================================================================
if [ -n "$PAD_HOST" ]; then
c_head "7. ALCANZAR EL PAD ($PAD_HOST)"
    if ping -c 1 -W 2 "$PAD_HOST" >/dev/null 2>&1; then
        c_ok "responde al ping"
    else
        c_warn "no responde al ping (puede estar bloqueado y aun asi funcionar)"
    fi
    if timeout 3 bash -c "echo > /dev/tcp/$PAD_HOST/22" >/dev/null 2>&1; then
        c_ok "puerto 22 abierto - se puede entrar por SSH"
    else
        c_err "puerto 22 cerrado o inalcanzable"
    fi
    if curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$PAD_HOST/server/info" 2>/dev/null | grep -q 200; then
        c_ok "Moonraker responde en http://$PAD_HOST/"
    else
        c_warn "Moonraker no responde (normal si el pad esta recien arrancado)"
    fi
fi

# =============================================================================
c_head "RESUMEN"
# =============================================================================
if [ "$FALLOS" -eq 0 ] && [ "$AVISOS" -eq 0 ]; then
    printf '\033[1;32mTodo listo. Puedes meter el portatil en la mochila.\033[0m\n'
elif [ "$FALLOS" -eq 0 ]; then
    printf '\033[1;33mListo, con %s aviso(s). Leelos, pero se puede trabajar.\033[0m\n' "$AVISOS"
else
    printf '\033[1;31m%s fallo(s) y %s aviso(s). Resuelvelos ANTES de salir de casa.\033[0m\n' "$FALLOS" "$AVISOS"
fi
echo
c_info "Siguiente paso:  cat $REPO_DIR/docs/RUNBOOK-EN-SITIO.md"
echo

[ "$FALLOS" -eq 0 ]
