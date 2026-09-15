#!/usr/bin/env python3
"""
Genera los iconos del tema claro invirtiendo la luminancia de los GRISES
(blanco -> negro, gris claro -> gris oscuro) y dejando intactos los colores
de acento (azules, rojos...). Asi los iconos disenados para fondo oscuro
quedan legibles sobre fondo claro sin perder el color con significado.
"""
import os
import re
import shutil
import sys

SRC = "/home/pi/KlipperScreen/styles/cupertino/images"
DST = "/home/pi/KlipperScreen/styles/cupertino-light/images"

# Acentos que queremos remapear en lugar de invertir
REMAP = {
    "#2196f3": "#007aff",   # azul material -> azul iOS claro
    "#b12f35": "#ff3b30",   # rojo -> rojo iOS
}

HEX6 = re.compile(r"#([0-9a-fA-F]{6})\b")
GRAY_TOLERANCE = 10


def convert(match):
    raw = match.group(0)
    low = raw.lower()
    if low in REMAP:
        return REMAP[low]
    r = int(low[1:3], 16)
    g = int(low[3:5], 16)
    b = int(low[5:7], 16)
    # ¿es un gris? (canales casi iguales)
    if max(r, g, b) - min(r, g, b) <= GRAY_TOLERANCE:
        return "#{:02x}{:02x}{:02x}".format(255 - r, 255 - g, 255 - b)
    return raw


def main():
    if not os.path.isdir(SRC):
        print("ERROR: no existe", SRC)
        return 1
    os.makedirs(DST, exist_ok=True)
    changed = total = 0
    for name in sorted(os.listdir(SRC)):
        sp = os.path.join(SRC, name)
        dp = os.path.join(DST, name)
        if not name.lower().endswith(".svg"):
            shutil.copy2(sp, dp)
            continue
        total += 1
        with open(sp, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        new = HEX6.sub(convert, text)
        with open(dp, "w", encoding="utf-8") as fh:
            fh.write(new)
        if new != text:
            changed += 1
    print("SVG procesados: {}  |  recoloreados: {}".format(total, changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
