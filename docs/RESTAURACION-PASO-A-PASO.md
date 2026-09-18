# Restauración de la Speeder Pad — paso a paso

Continuación del paso 3 de `RUNBOOK-EN-SITIO.md`. Escrito para seguirlo
entero sin ayuda, con la máquina delante.

**Punto de partida verificado el 2026-09-15:** la pad está en estado de
fábrica (Klipper v0.10.0-455 de junio 2022, 3 instancias FLSUN, layout
`klipper_config`). El MCU está sano y conserva el firmware bueno de la
sesión original — por eso da `Multi-byte msgtag not supported`: el host
volvió atrás, el MCU no.

---

## Datos de la máquina

| | |
|---|---|
| Acceso | `ssh v400` (alias ya configurado, sin contraseña) |
| IP | 192.168.1.32 — **por WiFi**, `eth0` caído |
| Contraseña de `sudo` | `flsun` |
| MCU | `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0` (CH340) |
| Perfil correcto | era `printer_1` |
| Backups | `config-pad/` (calibrado) · `backup-fabrica-2026-09-15/` (fábrica) |

---

## PASO 4 — Borrar las Flsun Builds

```bash
~/kiauh/kiauh.sh
```

**Klipper:** `3` (Remove) → `1` (Klipper) → `a` (marca las tres casillas:
Service, Local Repository, Python Environment) → `C` (Continue).

**Moonraker:** de vuelta en Remove → `2` (Moonraker) → `a` → `C`.

Deja **Mainsail** y **KlipperScreen** instalados. Mainsail es web estática y
se reapunta sola; KlipperScreen es tu única interfaz en la pantalla y se
reconfigura en el paso 8.

> El menú avisa: *"Configurations and/or any backups will be kept"*. Las
> configuraciones no se tocan.

Comprobación antes de seguir:

```bash
ls -d ~/klipper ~/klippy-env ~/moonraker ~/moonraker-env 2>&1   # no deben existir
systemctl list-units --all | grep -cE "klipper-[0-9]|moonraker-[0-9]"   # -> 0
```

---

## PASO 5 — Instalar las builds oficiales, UNA instancia

En kiauh: `1` (Install) → `1` (Klipper).

- Pregunta la versión de Python → **Python 3**
- Pregunta cuántas instancias → **1**

Luego, sin salir de Install: `2` (Moonraker), también **1 instancia**.

Esto crea el layout moderno: `/home/pi/printer_data/config`, nada que ver
con el `klipper_config` de FLSUN.

Comprobación:

```bash
ls ~/printer_data/config
systemctl is-active klipper moonraker      # -> active active (ya SIN número)
cd ~/klipper && git describe --tags        # apunta la versión que salga
```

**Apunta esa versión de Klipper.** Decide el paso 7.

---

## PASO 6 — Subir tus configuraciones calibradas

Desde el portátil, en el directorio del repositorio:

```bash
scp config-pad/printer.cfg config-pad/macros.cfg config-pad/variables.cfg \
    config-pad/neopixels.cfg config-pad/timelapse.cfg config-pad/moonraker.conf \
    v400:/home/pi/printer_data/config/
```

### Dos ajustes obligatorios antes de arrancar

**1. El puerto serie.** La config vieja usa una ruta `by-path` que cambia si
mueves el cable de puerto. Cámbiala por la `by-id`, que es estable:

```bash
ssh v400 "sed -i 's|^serial:.*|serial: /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0|' /home/pi/printer_data/config/printer.cfg"
ssh v400 "grep -n '^serial:' /home/pi/printer_data/config/printer.cfg"
```

**2. El acelerómetro.** `[include adxlmcu.cfg]` tiene que estar **comentado**
mientras el KUSBA no esté enchufado por USB. Si se queda activo sin la placa,
Klipper no arranca. Esto ya pasó una vez:

```bash
ssh v400 "grep -n 'adxlmcu' /home/pi/printer_data/config/printer.cfg"
```

Si aparece sin `#` delante, coméntalo.

Reinicia y mira el estado:

```bash
ssh v400 "sudo systemctl restart klipper moonraker"
ssh v400 "curl -s http://127.0.0.1:7125/printer/info"
```

---

## PASO 7 — Firmware del MCU (solo si hace falta)

Compara la versión del paso 5 con la que el MCU espera.

- **`state: ready`** → el firmware ya coincide. **Sáltate este paso entero.**
- **`Multi-byte msgtag not supported`** o cualquier *MCU Protocol error* →
  hay que reflashear.

### Compilar

```bash
ssh v400
cd ~/klipper && make clean && make menuconfig
```

Opciones exactas — **la interfaz es serie, NO USB**; equivocarla deja la
impresora incomunicada:

```
[*] Enable extra low-level configuration options
    Micro-controller Architecture ... STMicroelectronics STM32
    Processor model .................. STM32F103
    Bootloader offset ................ 28KiB bootloader
    Clock Reference .................. 8 MHz crystal
    Communication interface .......... Serial (on USART3 PB11/PB10)
    Baud rate ........................ 250000
```

Atajo: `scripts/klipper-mcu.config` del repositorio ya tiene estas opciones.

```bash
make -j4
./scripts/update_mks_robin.py out/klipper.bin out/Robin_nano35.bin
```

### Flashear

1. Copia `out/Robin_nano35.bin` a la **raíz** de una microSD en FAT32
2. Impresora **apagada** → mete la tarjeta → enciende
3. Espera. Si funcionó, el archivo se renombra a **`ROBIN_NANO35.CUR`**
4. Apaga, saca la tarjeta, enciende

```bash
ssh v400 "sudo systemctl restart klipper && sleep 15 && curl -s http://127.0.0.1:7125/printer/info"
```

Debe decir `"state": "ready"`.

---

## PASO 8 — KlipperScreen

Quedó apuntando a las instancias que ya no existen. Su configuración:

```bash
ssh v400 "ls ~/printer_data/config/KlipperScreen.conf ~/klipper_config/KlipperScreen.conf 2>&1"
```

Sube la tuya y reinicia:

```bash
scp config-pad/KlipperScreen.conf v400:/home/pi/printer_data/config/
ssh v400 "sudo systemctl restart KlipperScreen"
```

Si la pantalla se queda en negro o en error, mira el log:

```bash
ssh v400 "journalctl -u KlipperScreen -n 40 --no-pager"
```

---

## PASO 9 — NetworkManager — **el último**

> Este es el paso que puede dejarte sin acceso. Instalarlo tumba la red, y
> ahora mismo el WiFi es la única vía de entrada (`eth0` está caído).
> **Hazlo con un cable Ethernet puesto**, o asumiendo que puedes tener que ir
> a la máquina físicamente.

```bash
sudo apt-get install network-manager -y
```

Parecerá colgarse en `Processing triggers for systemd` y dará un error de
conexión abortada. **Es normal**, la wiki de Guilouz lo advierte.

```bash
sudo mkdir -p /etc/NetworkManager/conf.d
printf '[main]\nauth-polkit=false\n' | sudo tee /etc/NetworkManager/conf.d/any-user.conf
sudo systemctl -q disable dhcpcd; sudo systemctl -q stop dhcpcd
sudo systemctl enable NetworkManager
sudo systemctl -q --no-block start NetworkManager
nmcli device wifi connect "RedDelCliente" password "contraseña"
```

Esto es lo que se omitió la primera vez y la causa de todo el problema:
sin NetworkManager el cliente no puede cambiar de red desde la pantalla.

---

## PASO 10 — Recalibrar

**El orden importa**: cada paso depende del anterior.

```
rotation_distance → Z_OFFSET_CALIBRATION → ENDSTOPS_CALIBRATION
→ DELTA_CALIBRATION → BED_LEVELING → PID_BED → PID_HOTEND
→ input shaper (con el KUSBA)
```

Reutilizables tal cual desde el README (son térmicos y de extrusión):
`rotation_distance`, PID de cama y hotend, input shaper.

Hay que volver a medirlos sí o sí (son geométricos): z-offset, calibración
delta, malla de cama.

Para el input shaper, descomenta `[include adxlmcu.cfg]` **solo** con el
KUSBA conectado, y vuelve a comentarlo al terminar.

---

## PASO 11 — Cámara y timelapse

Instala Crowsnest desde kiauh (`1` Install → Crowsnest). La configuración de
`crowsnest.conf` y el override de systemd con el retardo de ~15 s están en el
README. Ese retardo es intencionado: evita que crowsnest arranque antes de que
el USB de la cámara esté listo.

---

## Verificación final

```bash
ssh v400 "curl -s http://127.0.0.1:7125/printer/info"          # state: ready
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.1.32/server/info       # 200
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.1.32/webcam/?action=snapshot
```

Reinicia la pad entera y confirma que vuelve sola al WiFi y que Klipper
queda en `ready` sin tocar nada.

---

## Avisos que cuestan caro olvidar

- **`[include adxlmcu.cfg]` comentado** sin el KUSBA puesto, o Klipper no
  arranca.
- **nginx corta a los 10 minutos con un 504.** Las calibraciones largas lo
  superan. El 504 **no es un fallo**: Klipper sigue trabajando. Consulta el
  estado, no esperes la respuesta.
- **Las macros de calibración se niegan a correr si `idle_timeout` está en
  `Printing`.** Espera a `Ready`.
- **Si el `z_offset` cambia más de ~0,5 mm** sin haber tocado boquilla ni
  soporte, es un error de medida, no un dato. Repite antes de encadenar
  `DELTA_CALIBRATION`, que propaga el fallo a toda la geometría.
- **El firmware del MCU sobrevive a la restauración de la microSD.** Vive en
  la placa. Por eso una pad recién restaurada da error de protocolo con un
  MCU que está perfectamente bien.

---

# Lo que pasó de verdad — ejecución del 2026-09-15

Resultado: **restauración completada**. Klipper `ready`, Moonraker activo,
Mainsail respondiendo, MCU conectado sin un solo byte inválido.

## El paso 7 no hizo falta

kiauh instaló **v0.13.0-762** y el MCU conservaba el firmware de
**v0.13.0-753**. Misma serie, nueve commits de diferencia: el protocolo no
cambió y conectaron sin reflashear. La microSD no se llegó a usar.

**Regla general:** no reflashees por prevención. Instala, arranca, y solo si
sale *MCU Protocol error* saca la tarjeta.

## El bloqueo real fue Python, no el firmware

La instalación de Moonraker abortó con:

```
ERROR: Package 'zeroconf' requires a different Python: 3.8.10 not in '>=3.10'
```

Moonraker moderno pide Python 3.10+, y Ubuntu 20.04 trae 3.8.10. Pero el
requisito real es `zeroconf>=0.131.0, <=0.150.0`: **dentro del rango hay
versiones válidas para 3.8**. El fallo no era de compatibilidad, era del
resolvedor: el venv se creaba con `pip 20.0.2`, que no sabe retroceder a una
versión anterior cuando la más nueva no encaja.

**La solución — actualizar pip dentro del entorno virtual:**

```bash
/home/pi/moonraker-env/bin/pip install -U "pip<25" setuptools wheel
cd /home/pi/moonraker
setsid nohup /home/pi/moonraker-env/bin/pip install -r scripts/moonraker-requirements.txt \
    > /tmp/mr-pip.log 2>&1 < /dev/null &
```

`pip<25` porque la 25 ya no soporta Python 3.8. Con el resolvedor nuevo, pip
eligió solo `zeroconf 0.136.2`, `pillow 10.4.0` y `tornado 6.4.2`.

Lanzarlo con `setsid nohup` y un log evita que se muera si se corta el SSH:
la compilación de Pillow y dbus-fast en armhf pasa de media hora.

Hecho esto, se relanza kiauh → Install → Moonraker → 1 instancia, y ya crea
el servicio: encuentra las dependencias puestas y el pip bueno en el venv.

## El `moonraker.conf` viejo NO se sobrescribe

El de `config-pad/` declara `update_manager` para **crowsnest**,
**moonraker-timelapse** y el **KlipperScreen de Guilouz**. Si los pones antes
de instalar esos componentes, Moonraker se llena de errores.

Se conservó el generado por kiauh (copia en `moonraker.conf.kiauh-orig`) y solo
se le añadió:

```ini
[machine]
shutdown_action: halt
```

Los bloques `update_manager` se van añadiendo **a medida que se instala cada
componente**, no antes.

## Detalles que ahorran tiempo

- `sudo` en el pad pide contraseña (`flsun`) salvo para `/usr/bin/systemctl`,
  que es NOPASSWD. Gestionar servicios no necesita contraseña.
- El `printer.cfg` de `config-pad/` **ya trae la ruta `by-id`** correcta. No
  hay que tocar el `serial:`.
- Las entradas `moonraker.service not-found` que quedan tras borrar son
  fantasmas de systemd, inofensivas.
- kiauh dibuja cajas de 57 columnas: en un panel estrecho se rompe el dibujo y
  se vuelve ilegible. Ensancha la terminal antes de navegar por sus menús.

## KlipperScreen: la interfaz antigua y el `Unauthorized`

Tras restaurar, la pantalla queda con el **fork de fábrica**
(`gitee.com/leexxiangyang/KlipperScreen`, de septiembre de 2022): interfaz
vieja y sin `material-blue`, que es de donde los temas `cupertino` sacan los
iconos. Por eso los temas propios no se pueden instalar sobre él.

**No hace falta ejecutar el instalador ni sudo.** El servicio de fábrica
apunta a `/home/pi/KlipperScreen/screen.py` con el venv
`/home/pi/.KlipperScreen-env`, así que basta con sustituir el directorio
manteniendo la ruta — el venv ya trae las dependencias:

```bash
git clone --depth 1 https://github.com/Guilouz/KlipperScreen-Flsun-Speeder-Pad.git ~/KlipperScreen-guilouz
sudo systemctl stop KlipperScreen
mv ~/KlipperScreen ~/KlipperScreen.fabrica      # red de seguridad
mv ~/KlipperScreen-guilouz ~/KlipperScreen
```

Temas (desde el portátil, y luego en el pad):

```bash
scp -r temas/cupertino temas/cupertino-light v400:/home/pi/KlipperScreen/styles/
```

```bash
cd ~/KlipperScreen
cp -r styles/material-blue/images styles/cupertino/
cp -r styles/material-blue/images styles/cupertino-light/
printf "styles/cupertino/\nstyles/cupertino-light/\n" >> .git/info/exclude
```

Sube `KlipperScreen.conf` a `~/printer_data/config/` y añade `theme: cupertino`
bajo `[main]`.

### El error `Unauthorized` (-32602)

Al arrancar, KlipperScreen no podrá listar gcodes y el log de Moonraker dirá:

```
Trusted Client attempt at user/api-key authentication failed.
Revoking trusted authentication.
```

**Causa:** KlipperScreen envía `moonraker_api_key` **vacía**, y Moonraker
moderno trata la cadena vacía como un intento fallido de autenticación — y le
retira la confianza que ya tenía por venir de `127.0.0.1`. Enviar una clave
vacía es peor que no enviar ninguna.

**Solución** — darle la clave real que genera el Moonraker nuevo:

```bash
KEY=$(curl -s http://127.0.0.1:7125/access/api_key | sed -E 's/.*"result":\s*"([^"]+)".*/\1/')
sed -i "/^\[printer FLSUN V400\]/a moonraker_api_key: $KEY" ~/printer_data/config/KlipperScreen.conf
sudo systemctl restart KlipperScreen
```

La clave cambia con cada instalación limpia de Moonraker: si se reinstala,
hay que volver a ponerla.

## Corrección al paso 9: NetworkManager ya viene instalado

En la imagen restaurada **NetworkManager ya está instalado y activo**
(`/usr/bin/nmcli` presente, `dhcpcd` inactivo). El `apt-get install
network-manager` del runbook —la parte capaz de tumbar la red— **no hace
falta**.

El problema real es otro: NM está corriendo pero **no gestiona el WiFi**.

```
wlan0   wifi   disconnected   --     ← la conexión la lleva wpa_supplicant por fuera
```

Faltan dos cosas, y ninguna corta la conexión en marcha:

```bash
sudo mkdir -p /etc/NetworkManager/conf.d
printf '[main]\nauth-polkit=false\n' | sudo tee /etc/NetworkManager/conf.d/any-user.conf
```

Y el perfil de la red, reciclando la contraseña ya guardada en el sistema — sin
que nadie tenga que reescribirla:

```bash
SSID=$(sudo grep -oP 'ssid="\K[^"]+' /etc/wpa_supplicant/wpa_supplicant.conf | head -1)
PSK=$(sudo grep -oP 'psk="\K[^"]+' /etc/wpa_supplicant/wpa_supplicant.conf | head -1)
sudo nmcli connection add type wifi con-name "$SSID" ifname wlan0 ssid "$SSID" \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PSK" connection.autoconnect yes
```

### El traspaso — el único momento con riesgo

```bash
sudo systemctl stop wpa_supplicant && sudo nmcli connection up "$(iwgetid -r)"
```

**No deshabilites `wpa_supplicant` de forma permanente hasta comprobar que NM
conecta.** Mientras no lo hagas, la red de seguridad es apagar y encender la
pad: al arrancar vuelve la configuración de siempre y se recupera el acceso sin
cable ni teclado.

Solo cuando NM conecte de forma estable:

```bash
sudo systemctl disable wpa_supplicant
```

Hazlo **después** de calibrar, no antes: si pierdes la red justo antes de una
sesión de calibración, te quedas sin las dos cosas.

---

# AVISO CRÍTICO — cómo se perdió el acceso el 2026-09-15

La restauración terminó bien (Klipper `ready`, Mainsail, pantalla con temas) y
**aun así hubo que reinstalar desde cero**, por un fallo al preparar
NetworkManager. Lee esto antes de tocar la red.

## Qué se hizo mal

Se creó el perfil WiFi extrayendo SSID y contraseña **por separado** del
`wpa_supplicant.conf`:

```bash
# MAL — no garantiza que ssid y psk sean del mismo bloque
SSID=$(grep -oP 'ssid="\K[^"]+' ... | head -1)
PSK=$(grep -oP 'psk="\K[^"]+'  ... | head -1)
nmcli connection add ... connection.autoconnect yes
```

Dos errores encadenados:

1. **El emparejamiento.** El fichero tenía dos redes. Si una guarda la clave
   cifrada (sin comillas, como deja `wpa_passphrase`) y la otra en texto plano,
   el `head -1` de cada campo devuelve **datos de bloques distintos**: el perfil
   queda con el SSID de una red y la contraseña de otra.
2. **`autoconnect yes` con NetworkManager ya activo.** No es inofensivo: NM
   toma la interfaz de inmediato, se la quita a `wpa_supplicant` e intenta
   autenticarse con la clave equivocada. El WiFi cae y no vuelve.

Sin red no hay SSH; sin SSH no se puede deshacer. Y en esta máquina **no hay
puerta trasera**: el cambio de consola (`Ctrl+Alt+F2`) congela el pad porque
KlipperScreen ocupa el framebuffer, y el sistema vive en memoria interna, no en
la microSD, así que la tarjeta no se puede editar desde otro equipo.

## Cómo hacerlo bien

**Verifica el emparejamiento antes de crear nada:**

```bash
sudo grep -A3 -E '^\s*network=' /etc/wpa_supplicant/wpa_supplicant.conf
```

Mira bloque por bloque qué `psk` acompaña a qué `ssid`. Si la clave está
cifrada (64 caracteres hex sin comillas), **no la extraigas**: pídele al dueño
la contraseña en texto.

**Crea el perfil SIN autoconexión:**

```bash
sudo nmcli connection add type wifi con-name "$SSID" ifname wlan0 ssid "$SSID" \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PSK" connection.autoconnect no
```

**Y activa con red de seguridad**, un temporizador que lo deshace si te quedas
fuera:

```bash
sudo bash -c 'nohup sh -c "sleep 180; ping -c3 -W2 192.168.1.1 >/dev/null 2>&1 || \
  { systemctl stop NetworkManager; systemctl start wpa_supplicant; }" >/dev/null 2>&1 &'
sudo nmcli connection up "$SSID"
```

Si a los tres minutos no hay pasarela, la máquina se devuelve sola a
`wpa_supplicant`. Solo cuando confirmes que NM conecta de forma estable:

```bash
sudo nmcli connection modify "$SSID" connection.autoconnect yes
sudo systemctl disable wpa_supplicant
```

## Regla de oro

**Nada que toque la red se ejecuta sin una vía de recuperación probada de
antemano.** En este pad, las únicas son: otra interfaz de red viva (un
adaptador USB‑Ethernet, que conviene tener en la caja de herramientas) o
reinstalar. El teclado no vale y la microSD tampoco.

---

# Estado final tras la segunda restauración (2026-09-15, noche)

Todo operativo. La segunda vuelta llevó una fracción de la primera porque los
tres escollos ya estaban resueltos aquí.

| Componente | Estado |
|---|---|
| Klipper | v0.13.0-762 · `ready` |
| Moonraker | activo · `klippy_connected` |
| Mainsail | HTTP 200 en `http://192.168.1.32` |
| KlipperScreen | fork de Guilouz + tema `cupertino` |
| Firmware MCU | intacto — **no hizo falta tocarlo, por segunda vez** |
| Zona horaria | `America/Bogota` |
| `sdbus` | instalado (panel de red listo si algún día entra NM) |

## Decisión sobre NetworkManager: NO se instala

La red la lleva `wpa_supplicant`, que funciona y es estable. NetworkManager
**no viene en la imagen de fábrica** y su instalación es el paso que costó la
primera restauración.

Para cambiar de red se usa el script, ya instalado en `/home/pi/`:

```bash
sudo bash /home/pi/conectar-wifi.sh --diagnostico          # mirar sin tocar
sudo bash /home/pi/conectar-wifi.sh "RedNueva" "clave"     # cambiar
```

Detecta el gestor activo, hace copia de seguridad y aplica por el método
correcto.

**Consecuencia asumida:** el panel de red de la pantalla táctil no funcionará
(necesita NetworkManager por D-Bus). Cambiar de WiFi requiere SSH. Es el precio
de no arriesgar el acceso, y se aceptó a conciencia.

### Si algún día se quiere el panel de la pantalla

Requisito previo: **un adaptador USB‑Ethernet conectado y funcionando**, como
vía de recuperación. Sin él no se intenta. Con él, el procedimiento seguro está
en la sección «AVISO CRÍTICO» de este documento.

## Pendiente

Recalibrar lo geométrico — z-offset, delta y malla, en ese orden. Los valores
térmicos y de extrusión del README siguen siendo válidos.

---

# Rescate por USB — la puerta trasera que sí existe

Descubierto al leer `/etc/rc.local`, que en cada arranque ejecuta
`/usr/sbin/cfgguard.sh`. Ese script, además de pintar el logo y levantar el
WiFi, termina con:

```bash
if [ -f /home/pi/gcode_files/USB-Disk/update.sh ]; then
        sudo bash /home/pi/gcode_files/USB-Disk/update.sh
fi
```

**El pad ejecuta como root cualquier `update.sh` que encuentre ahí al
arrancar.** Es la vía de entrada que no teníamos el 2026-09-15, cuando el pad
quedó sin red: sin SSH, sin consola (`Ctrl+Alt+F2` congela la pantalla) y sin
poder editar la tarjeta (el sistema vive en memoria interna).

## Cómo se usa

En `scripts/usb-rescate/` está el script preparado.

1. Copiar `update.sh` a la **raíz de una memoria USB**
2. Si hay que conectar a otra red, crear al lado un `wifi.txt`:

```
SSID=NombreDeLaRed
PASS=LaContrasena
```

3. Conectar el USB al pad y **encender**
4. Esperar a que arranque del todo (dos o tres minutos)
5. Apagar, sacar el USB y abrir **`rescate.log`** en la memoria: ahí está la IP
   obtenida y el comando `ssh` listo para copiar

Sin `wifi.txt` solo reactiva la red ya configurada. Con él, añade la red nueva
con `priority=99` **sin borrar las anteriores**, y guarda copia del
`wpa_supplicant.conf` original.

Lo primero que hace es **detener y deshabilitar NetworkManager**, que fue la
causa exacta del bloqueo de aquel día.

## Cómo cambiar de WiFi con esto

Sirve igual para lo cotidiano, no solo para emergencias: si el pad se lleva a
casa de un cliente y allí no hay forma de entrar por SSH, se prepara el USB con
el `wifi.txt` de la red del cliente, se enciende con él puesto, y el pad
aparece en su red. El `rescate.log` dice en qué IP.

## Cautelas

- El mecanismo ejecuta **como root** y sin preguntar: no dejes memorias USB de
  terceros conectadas al encender.
- El `wifi.txt` lleva la contraseña **en texto plano**. Bórralo de la memoria
  cuando termines.
- Verifica una vez que la memoria USB se monta realmente en
  `/home/pi/gcode_files/USB-Disk/`; si el punto de montaje fuese otro, el
  script no llegaría a ejecutarse.
