#!/bin/bash
# =============================================================================
#  Arregla el "Unauthorized" de la pantalla tactil
#
#  Sintoma: la pantalla no lista los gcodes y el log de Moonraker dice
#     Trusted Client attempt at user/api-key authentication failed.
#     Revoking trusted authentication.
#     JSON-RPC Request Error - server.files.list, Code: -32602, Unauthorized
#
#  Causa: KlipperScreen envia moonraker_api_key VACIA. Moonraker moderno trata
#  la cadena vacia como intento fallido de autenticacion y le retira la
#  confianza que le daba por venir de 127.0.0.1. Mandar una clave vacia es peor
#  que no mandar ninguna.
#
#  La clave cambia con cada instalacion limpia de Moonraker: si se reinstala,
#  hay que volver a ejecutar esto.
#
#  USO:  bash fix-apikey.sh        (no necesita sudo salvo para reiniciar)
# =============================================================================

set -u
CONF="/home/pi/printer_data/config/KlipperScreen.conf"

[ -f "$CONF" ] || { echo "No encuentro $CONF"; exit 1; }

echo "Pidiendo la API key a Moonraker..."
KEY=$(curl -s --max-time 10 http://127.0.0.1:7125/access/api_key | sed -E 's/.*"result":\s*"([^"]+)".*/\1/')

if [ ${#KEY} -le 16 ]; then
    echo "ERROR: Moonraker no devolvio una clave valida."
    echo "Comprueba que este activo:  systemctl is-active moonraker"
    exit 1
fi
echo "Clave obtenida: ${KEY:0:8}..."

cp "$CONF" "${CONF}.bak_$(date +%Y%m%d_%H%M%S)"
sed -i '/^moonraker_api_key:/d' "$CONF"

if grep -q "^\[printer " "$CONF"; then
    sed -i "/^\[printer /a moonraker_api_key: $KEY" "$CONF"
    echo "Clave escrita en $CONF"
else
    echo "ERROR: no hay ninguna seccion [printer ...] en el fichero"
    exit 1
fi

echo "Reiniciando KlipperScreen..."
sudo systemctl restart KlipperScreen
sleep 15

ERR=$(tail -40 /home/pi/printer_data/logs/KlipperScreen.log 2>/dev/null | grep -ic unauthorized)
if [ "$ERR" = "0" ]; then
    echo "LISTO - sin errores de autorizacion"
else
    echo "Siguen apareciendo $ERR errores. Revisa el log:"
    echo "  tail -40 /home/pi/printer_data/logs/KlipperScreen.log"
fi
