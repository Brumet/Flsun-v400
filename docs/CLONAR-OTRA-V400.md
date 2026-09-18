# Dejar operativa otra FLSUN V400

Guía corta para montar una segunda máquina igual que la de referencia. El
trabajo pesado lo hace `scripts/provision.sh`; aquí solo está lo que hay que
hacer con las manos.

**Tiempo:** unas dos horas, de las cuales hora y media es esperar.

---

## Lo que necesitas

- [ ] microSD de 32 GB o más
- [ ] Imagen **V1.2** del Speeder Pad (la **V1.4 no permite SSH** — no sirve)
- [ ] Red WiFi con internet
- [ ] Un ordenador para entrar por SSH
- [ ] **Recomendado:** un adaptador USB‑Ethernet. Es la única vía de rescate si
      el pad se queda sin red.

No hace falta microSD para el firmware del MCU: en las dos restauraciones de
2026‑09‑15 **no hubo que reflashear**. Ver más abajo.

---

## 1 · Restaurar la imagen

Graba la V1.2 en la microSD, métela en el pad y enciende. Tarda entre diez y
quince minutos y termina con una barra verde.

Cuando acabe: **apaga, saca la tarjeta y enciende otra vez.** Si la dejas
puesta, vuelve a grabar la imagen en bucle.

---

## 2 · Conectar el WiFi desde la pantalla

La interfaz de fábrica sí puede hacerlo, y es el único momento en que hace
falta. Apunta la IP que muestre.

---

## 3 · Conectar el MCU

Con el pad ya arrancado:

1. Enciende **la impresora** (sin corriente en la placa no aparece el puerto)
2. Conecta el cable USB entre la placa y el pad

Comprueba desde tu ordenador que el puerto existe:

```bash
ssh pi@LA_IP "ls /dev/serial/by-id/"
```

Debe salir algo como `usb-1a86_USB_Serial-if00-port0`. Si no aparece, revisa el
cable y que la impresora esté encendida.

---

## 4 · Lanzar el aprovisionamiento

```bash
ssh pi@LA_IP
git clone https://github.com/Brumet/Flsun-v400.git
sudo bash Flsun-v400/scripts/provision.sh
```

Contraseña de `pi`: `flsun`

A partir de ahí no hay que tocar nada durante **60‑90 minutos**. Habrá silencios
largos mientras compila `pillow` y `dbus-fast` sobre armhf: es normal, no lo
interrumpas.

El script deja registro en `/var/log/flsun-provision.log`. Si algo falla a
mitad, **se puede volver a ejecutar**: detecta lo que ya está hecho.

### Qué hace, por fases

| | |
|---|---|
| 1 | Retira las tres instancias de FLSUN y sus forks |
| 2 | Paquetes del sistema (**sin** NetworkManager, a propósito) |
| 3 | Klipper oficial, **una sola instancia**, layout `printer_data` |
| 4 | Moonraker **con el arreglo de pip** que evita el fallo de `zeroconf` |
| 5 | Tus configuraciones calibradas + ruta del MCU por `by-id` |
| 6 | KlipperScreen de Guilouz + temas `cupertino` + `sdbus` |
| 7 | API key de la pantalla |
| 8 | Verificación y resumen |

---

## 5 · Comprobar

```bash
curl -s http://LA_IP:7125/printer/info
```

Tiene que decir `"state":"ready"`. Y `http://LA_IP` debe abrir Mainsail.

En la pantalla táctil, el menú con el tema oscuro estilo iOS.

---

## 6 · Lo que queda a mano

**Calibrar lo geométrico**, en este orden — cada paso se apoya en el anterior:

```
Z_OFFSET_CALIBRATION → ENDSTOPS_CALIBRATION → DELTA_CALIBRATION → BED_LEVELING
```

Los valores térmicos y de extrusión del README (PID, `rotation_distance`, input
shaper) **se reutilizan tal cual**: no dependen de esta máquina en concreto.

**Zona horaria**, si no es Colombia:

```bash
sudo timedatectl set-timezone America/Bogota
```

**Prepara el USB de rescate** y guárdalo con la máquina: copia
`scripts/usb-rescate/update.sh` a una memoria. Es la única forma de entrar si
algún día se queda sin red.

---

## El firmware del MCU: casi nunca hay que tocarlo

El firmware vive **en la placa**, no en la microSD. Sobrevive a cualquier
restauración del pad.

Por eso un pad recién restaurado da `MCU Protocol error`: el host vuelve a la
v0.10.0 de fábrica y no entiende al MCU, que sigue con la versión nueva. **No es
una avería**, y se arregla solo al instalar Klipper oficial.

Solo hay que reflashear si, **después** de que el script termine, sigue diciendo
`MCU Protocol error`. El procedimiento está en el PASO 7 de
[RESTAURACION-PASO-A-PASO.md](RESTAURACION-PASO-A-PASO.md), con un aviso que
cuesta caro olvidar: la interfaz es **Serial en USART3 PB11/PB10**, no USB.

---

## La red: NetworkManager, solo con el script

Si quieres que el cliente pueda cambiar de WiFi **desde la pantalla táctil**,
hace falta NetworkManager. Y se instala con esto, nunca a mano:

```bash
sudo bash Flsun-v400/scripts/migrar-networkmanager.sh
```

Ese script existe precisamente porque hacerlo a mano sale mal. Lee la
contraseña que ya está guardada en el pad, **crea el perfil antes de instalar
NetworkManager**, comprueba que haya IP al terminar y, si no la hay, restaura
`wpa_supplicant` + `dhclient`. Se relanza en segundo plano, así que sobrevive a
que se caiga tu SSH.

Para reconectar después, si NM pierde la red:

```bash
sudo systemd-run --unit=conectar-nm bash /home/pi/conectar-nm.sh
```

### Lo que NO hay que hacer

**Nunca** crear el perfil a mano con `nmcli connection add ... autoconnect yes`
mientras `wpa_supplicant` tiene la interfaz. El 15 de septiembre de 2026 eso
dejó un pad incomunicado y obligó a reinstalar desde cero. Dos errores a la vez:
el SSID y la contraseña se extrajeron de bloques distintos del fichero, y
`autoconnect` hizo que NetworkManager reclamara `wlan0` de inmediato con la
clave equivocada.

Recuérdalo porque esta máquina **no tiene puerta trasera**:

- `Ctrl+Alt+F2` **congela el pad** — KlipperScreen ocupa el framebuffer
- El sistema vive en memoria interna: **la microSD no se puede editar**
- Sin red no hay SSH, y sin SSH no se puede deshacer

Por eso conviene tener el **USB de rescate** preparado antes de tocar la red, y
mejor aún un adaptador USB‑Ethernet.

Para cambiar de red sin NetworkManager, el aprovisionamiento deja instalado:

```bash
sudo bash /home/pi/conectar-wifi.sh --diagnostico        # mirar sin tocar
sudo bash /home/pi/conectar-wifi.sh "Red" "clave"        # cambiar
```

La historia completa, en el **AVISO CRÍTICO** de
[RESTAURACION-PASO-A-PASO.md](RESTAURACION-PASO-A-PASO.md).

---

## Si algo sale mal

| Síntoma | Qué mirar |
|---|---|
| `zeroconf requires Python >=3.10` | El script ya lo evita. Si sale, el pip del venv no se actualizó: `pip install -U 'pip<25'` dentro de `moonraker-env` |
| Pantalla con `Unauthorized` | `bash scripts/fix-apikey.sh` |
| Pantalla: `No module named 'sdbus'` | Falta `libsystemd-dev`; instálalo y repite la fase 6 |
| `mcu: Unable to connect` | Impresora apagada o cable USB suelto |
| `MCU Protocol error` tras terminar | Ahora sí toca reflashear: PASO 7 |
| Mainsail no carga | `systemctl status nginx moonraker` |
| Sin red y sin SSH | El USB de rescate. Si no lo preparaste, toca reinstalar |
