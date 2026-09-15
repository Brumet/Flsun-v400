# FLSUN V400 + Speeder Pad

Configuración, temas y utilidades para una FLSUN V400 con Speeder Pad corriendo
las builds oficiales de Klipper según la [wiki de Guilouz](https://github.com/Guilouz/Klipper-Flsun-Speeder-Pad/wiki).

---

## Trabajo en sitio

Si vas a ir donde está la máquina con un portátil, sigue
**[`docs/RUNBOOK-EN-SITIO.md`](docs/RUNBOOK-EN-SITIO.md)**: qué meter en la
mochila, cómo entrar al pad con un cable, y el orden exacto de las cosas.

Antes de salir de casa, con WiFi todavía:

```bash
bash scripts/preparar-portatil.sh
```

Deja el portátil listo —dependencias, `paramiko`, repositorio al día, permisos—
y verifica que no falte nada. `--verificar` comprueba sin tocar nada.

---

## Contenido

| Carpeta | Qué hay |
|---|---|
| `config-pad/` | Ficheros de configuración del pad (Klipper, Moonraker, KlipperScreen, macros) |
| `temas/` | Dos temas propios para KlipperScreen, oscuro y claro |
| `scripts/` | Preparar el portátil antes de salir, y conectar el pad a una red WiFi nueva |
| `docs/` | Instrucciones de red y gráficas de resonancia |
| `Klipper-Flsun-Speeder-Pad-main/` | Copia del repositorio de Guilouz |
| `speeder_pad_files/` | Ficheros de sistema del pad (sshd, banner, MOTD) |

> **No incluido por tamaño:** la imagen de restauración del pad (15 GB) y el
> software de terceros (MobaXterm, Raspberry Pi Imager). Las rutas de descarga
> están en el `.gitignore`.

---

## Hardware

| | |
|---|---|
| Impresora | FLSUN V400 (delta, radio de impresión 152 mm) |
| Placa | MKS Robin Nano V2.0 — STM32F103 |
| Controlador | FLSUN Speeder Pad · Ubuntu 20.04 · kernel aarch64, **userspace armhf** |
| Acelerómetro | KUSBA v2.4 (Isik's Tech) — RP2040 + ADXL345, firmware Rampon |
| Cámara | EMEET SmartCam Nova 4K vía Crowsnest |

---

## Firmware del MCU

La placa **no habla por USB nativo**: usa un puente CH340 conectado a USART3.
Compilar con la interfaz equivocada deja la impresora incomunicada.

Opciones correctas en `make menuconfig`:

```
[*] Enable extra low-level configuration options
    Micro-controller Architecture ... STMicroelectronics STM32
    Processor model .................. STM32F103
    Bootloader offset ................ 28KiB bootloader
    Clock Reference .................. 8 MHz crystal
    Communication interface .......... Serial (on USART3 PB11/PB10)
    Baud rate ........................ 250000
```

Conversión y flasheo:

```bash
./scripts/update_mks_robin.py out/klipper.bin out/Robin_nano35.bin
```

El `.bin` va a la raíz de una microSD en FAT32. Al encender la impresora se
graba y el archivo se renombra a `ROBIN_NANO35.CUR` — esa es la confirmación
de que funcionó.

---

## Calibración

Todos estos valores están **medidos en esta máquina**, no son los genéricos.

### Input shaper

Medido con el KUSBA montado en el efector.

```ini
shaper_type_x: ei     shaper_freq_x: 36.0
shaper_type_y: ei     shaper_freq_y: 39.0
```

La resonancia principal está en ~33 Hz en ambos ejes y **no se puede subir**:
es intrínseca a la geometría de la máquina (brazos largos, chasis alto). Se
comprobó midiendo tres veces —sobre mesa, en el suelo con tornillería apretada,
y tras tensar correas— y la frecuencia no se movió. Lo que sí bajó un 40% fue la
amplitud del pico, gracias a tensar las correas.

### Aceleración

```ini
max_accel: 3000
```

`calibrate_shaper.py` recomienda no pasar de 2400–2800 con el filtro `ei` para
evitar redondeo de esquinas. El valor genérico de 10000 produce piezas con
detalle perdido.

### PID

```ini
# extruder
pid_kp: 26.494   pid_ki: 1.879   pid_kd: 93.391
# heater_bed
pid_kp: 72.486   pid_ki: 2.301   pid_kd: 570.831
```

### Extrusor

```ini
rotation_distance: 4.545
```

Medido con el método de Klipper: marca a 120 mm, extruir 100, quedaron 19.

### Palpador

Ajustado para precisión en lugar de velocidad. `PROBE_ACCURACY` da una
desviación estándar de **0,0014 mm** — el límite físico de la máquina, que es un
microstep (40 mm ÷ (200 × 64) = 0,003125 mm).

```ini
speed: 5
samples: 5
samples_result: median
sample_retract_dist: 4
samples_tolerance: 0.0125
samples_tolerance_retries: 10
```

### Dilatación térmica

El `z_offset` se calibra en frío, pero al calentar el hotend a 220 °C el conjunto
se alarga unos **0,11 mm hacia la cama**. La dilatación de la cama es
despreciable en comparación (~0,007 mm).

Por eso la primera capa sale baja tras calibrar en frío, y se corrige con
babysteps durante una impresión real. Guilouz sobrescribe `SET_GCODE_OFFSET`
para que **guarde el valor solo** en `variables.cfg`; no hay que usar
`SAVE_CONFIG` para el z-offset.

---

## Temas para KlipperScreen

Dos temas propios, alternables desde los ajustes del pad.

- **`cupertino`** — oscuro, paleta de sistema iOS
- **`cupertino-light`** — claro, fondo `#F2F2F7`

Criterio de diseño: **sin `box-shadow` ni degradados**. El pad renderiza por
software y las sombras se recalculan en cada redibujado (temperaturas, gráfica,
progreso). La profundidad se consigue con superficies planas y bordes de 1 px,
que salen prácticamente gratis. Tipografía Ubuntu en lugar de la DejaVu Sans
por defecto.

### Instalación

KlipperScreen **solo** carga temas desde su propio directorio, así que hay que
copiarlos dentro del repositorio y excluirlos localmente para no romper las
actualizaciones automáticas:

```bash
cp -r temas/cupertino ~/KlipperScreen/styles/
cp -r ~/KlipperScreen/styles/material-blue/images ~/KlipperScreen/styles/cupertino/
echo 'styles/cupertino/' >> ~/KlipperScreen/.git/info/exclude
```

Usar `.git/info/exclude` y no `.gitignore`: el primero no está versionado, así
que el repositorio sigue limpio y `git status` no detecta cambios.

Activar añadiendo a la sección `[main]` de `KlipperScreen.conf`:

```ini
theme: cupertino
```

### Tema claro: los iconos

Los 103 SVG de KlipperScreen están hechos para fondo oscuro (`#ffffff` aparece
103 veces). Sobre blanco serían invisibles. `temas/recolor_icons.py` invierte la
luminancia **solo de los grises** y respeta los colores con significado.

---

## Cámara

Crowsnest arrancaba antes de que el USB de la cámara terminara de enumerarse y
moría con `ERROR: Start of ustreamer failed`, dejando `/webcam/` en HTTP 502
aunque `systemctl` dijera `active`.

Solución en `/etc/systemd/system/crowsnest.service.d/override.conf`:

```ini
[Unit]
StartLimitIntervalSec=0

[Service]
ExecStartPre=/bin/sleep 15
Restart=on-failure
RestartSec=10
```

> `pgrep ustreamer` devuelve 0 aunque funcione, porque corre como
> `ustreamer.bin`. Comprobar siempre con la URL, no con pgrep.

---

## Acelerómetro KUSBA

La variante **Rampon** usa una configuración distinta de la que circula por
internet: pines con nombre y **sin** `spi_bus`.

```ini
[mcu adxl]
serial: /dev/serial/by-id/usb-Anchor_Rampon-if00

[adxl345]
cs_pin: adxl:CS
axes_map: x,-z,y
```

> **Importante:** la línea `[include adxlmcu.cfg]` debe estar **comentada**
> mientras el KUSBA no esté conectado. Si se deja activa sin la placa, Klipper
> no arranca.

La primera lectura del ADXL siempre sale inválida por diseño: ejecutar
`ACCELEROMETER_QUERY` una vez antes de medir resonancias.

---

## Red

El panel de red de KlipperScreen necesita **NetworkManager**. Sin él aparece
*"Failed to detect NetworkManager service"* y no se puede cambiar de WiFi desde
la pantalla.

`scripts/conectar-wifi.sh` conecta el pad a una red nueva sin necesidad de
NetworkManager: detecta si la red la gestiona `netplan`, `wpa_supplicant` o
NetworkManager, hace copia de seguridad y verifica que haya IP.

```bash
sudo bash conectar-wifi.sh --diagnostico          # solo mira, no toca nada
sudo bash conectar-wifi.sh "MiRed" "MiContrasena"
```

Ver `docs/INSTRUCCIONES.md` para el procedimiento completo.

> Si la máquina va a cambiar de dueño, **instalar NetworkManager antes de
> entregarla**. Sin él, el comprador no puede conectarla a su propia red.

---

## Notas de mantenimiento

- Las macros de calibración de Guilouz se niegan a ejecutarse si
  `idle_timeout` está en `Printing`. Cualquier comando reciente deja ese estado
  unos segundos, así que hay que esperar a `Ready` antes de lanzarlas.
- nginx corta las peticiones HTTP a los 10 minutos con un 504. Las
  calibraciones largas lo superan: **el 504 no significa fallo**, Klipper sigue
  trabajando. Hay que consultar el estado en lugar de esperar la respuesta.
- `pip` compila desde fuente en este pad (userspace armhf, sin wheels
  precompiladas). Instalar numpy en `klippy-env` llevó unos 15 minutos.
- Moonraker **no se puede actualizar** más allá de v0.10.0: las versiones
  nuevas exigen Python ≥ 3.10 y el pad tiene 3.8.10 sobre Ubuntu 20.04.
