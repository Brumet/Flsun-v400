# Runbook: qué hacer con el portátil delante de la máquina

Guía de campo. Pensada para seguirla en casa del cliente, sin depender de
recordar nada.

---

## Antes de salir de casa, mete en la mochila

- [ ] Portátil con Linux
- [ ] **Cable de red Ethernet** (el elemento clave)
- [ ] Una microSD en FAT32 — **solo si vas a reflashear el firmware**
- [ ] **Portátil preparado y verificado**, con esto:

```bash
git clone https://github.com/Brumet/Flsun-v400.git
bash Flsun-v400/scripts/preparar-portatil.sh
```

Instala las dependencias (`git`, `ssh`, `scp`, `curl`, `python3`) y `paramiko`,
deja el repositorio al día, pone permisos de ejecución y verifica que no falte
nada. Termina con un resumen: si dice **«Todo listo»**, el portátil puede ir a
la mochila. Con `--verificar` solo comprueba, sin instalar ni tocar nada.

> Hazlo **en casa, con WiFi**. En casa del cliente puede que no haya internet
> para el portátil, y ahí ya es tarde para descubrir que falta un paquete.

---

## PASO 0 — Decidir qué vas a hacer

| Situación | Qué hacer |
|---|---|
| La máquina imprime bien y solo falla el WiFi | **Ruta rápida** (20 min) |
| La máquina está rota de verdad y no arranca | Ruta de restauración (media jornada) |

> La ruta de restauración **borra toda la calibración**. No se usa para arreglar
> un problema de red. Si dudas, ruta rápida.

---

# RUTA RÁPIDA (20 minutos)

## 1. Conectar el portátil al pad

Cable Ethernet **directo del portátil al pad**. No hace falta pasar por el
router del cliente ni tocar su instalación.

```bash
ssh pi@speeder-pad.local
```

Si `.local` no resuelve, en el portátil: configuración de red → perfil del cable
→ IPv4 → método **«Compartido con otros equipos»**. El portátil hace de router y
le da IP al pad. Vuelve a intentar el SSH.

## 2. Copia de seguridad — **esto primero, siempre**

Desde el portátil, antes de tocar nada:

```bash
scp -r pi@speeder-pad.local:/home/pi/printer_data/config ./backup-v400-$(date +%F)
```

Se lleva `printer.cfg` con toda la calibración, la malla de cama,
`variables.cfg`, las macros y `moonraker.conf`. **Si algo sale mal después,
esto lo salva todo.**

## 3. Conectar el pad al WiFi del cliente

```bash
scp scripts/conectar-wifi.sh pi@speeder-pad.local:/home/pi/
ssh pi@speeder-pad.local
sudo bash /home/pi/conectar-wifi.sh --diagnostico
sudo bash /home/pi/conectar-wifi.sh "RedDelCliente" "contraseña"
```

Apunta la IP que devuelve: es la dirección de Mainsail.

## 4. Instalar NetworkManager

Para que el cliente pueda cambiar de red desde la pantalla táctil sin llamarte.
**Hazlo con el cable Ethernet aún puesto**, por si algo falla.

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

## 5. Comprobar y marcharse

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://IP_DEL_PAD/server/info   # -> 200
curl -s -o /dev/null -w "%{http_code}\n" http://IP_DEL_PAD/webcam/?action=snapshot
```

Quita el cable. Reinicia el pad y confirma que se reconecta solo al WiFi.

---

# RUTA DE RESTAURACIÓN (solo si la máquina está rota)

> Devuelve el pad a fábrica. **Se pierde absolutamente todo**: Klipper
> v0.13.0-753, Moonraker, Mainsail, KlipperScreen de Guilouz, los temas, la
> cámara, el timelapse y **toda la calibración**.

## Orden obligatorio

1. **Restaurar la imagen** — microSD de 32 GB+, imagen **V1.2** (la V1.4 no
   permite SSH). Insertar, encender, esperar 10-15 min hasta la barra verde.
2. **Conectar a WiFi** desde la pantalla — la imagen de fábrica sí puede.
3. **Update Dependencies** de la wiki de Guilouz.
   **Esta vez sí, instalar NetworkManager**: es el paso que se omitió la
   primera vez y la causa de todo este problema.
4. **Delete Flsun Builds** con kiauh.
5. **Install Official Builds (1 instancia)** con kiauh.
6. **Subir configuraciones** desde `config-pad/` de este repositorio.
7. **Recompilar y flashear el firmware del MCU** — opciones exactas en el
   README. Ojo: `Serial (on USART3 PB11/PB10)`, **no USB**.
8. **Recalibrar** en este orden:
   `rotation_distance` → `Z_OFFSET_CALIBRATION` → `ENDSTOPS_CALIBRATION` →
   `DELTA_CALIBRATION` → `BED_LEVELING` → `PID_BED` → `PID_HOTEND` →
   input shaper con el KUSBA.
9. **Reinstalar los temas** — instrucciones en el README.
10. **Cámara y timelapse** — `crowsnest.conf` y el override de systemd están
    documentados en el README.

Los valores de referencia están todos en el README. Los térmicos y de extrusión
(PID, `rotation_distance`, input shaper) se pueden reutilizar tal cual. Los
geométricos (z-offset, delta, malla) **hay que volver a medirlos**.

---

## Si quieres que te ayude estando allí

Abre **Claude Code en el portátil que llevas**, y ábrelo **en local, desde su
terminal**. Este punto no es un detalle: decide si puedo ayudarte o no.

| Dónde abres la sesión | ¿Alcanza el pad? |
|---|---|
| Terminal del portátil que está delante de la máquina | **Sí** |
| Claude Code en la web o en el móvil | **No** |
| Terminal del PC de casa, estando tú en casa del cliente | **No** |

Una sesión abierta desde la web **no corre en tu portátil**: corre en un
contenedor de Anthropic, con su propia red. Desde ahí no veo tu red local, ni
`192.168.x.x`, ni el pad — no importa que me pases la IP, no hay ruta hasta ella.
Solo llego a la máquina donde se ejecuta la sesión.

Así que la regla es: **la sesión tiene que nacer en el portátil que tiene el
cable puesto**. Si `preparar-portatil.sh` terminó con «Todo listo», ya tiene
`paramiko` y no hay nada más que instalar.

Para confirmar antes de empezar que ese portátil alcanza el pad:

```bash
bash scripts/preparar-portatil.sh --verificar --pad speeder-pad.local
```

---

## Avisos que conviene recordar

- `[include adxlmcu.cfg]` está **comentado** en `printer.cfg`. Solo se
  descomenta con el KUSBA conectado por USB; si se deja activo sin la placa,
  **Klipper no arranca**. Esto ya pasó una vez.
- La cámara tarda ~15 s en aparecer al encender: es un retardo puesto a
  propósito para que crowsnest no arranque antes de que el USB esté listo.
- nginx corta las peticiones HTTP a los 10 minutos con un **504**. Las
  calibraciones largas lo superan: el 504 **no significa fallo**, Klipper sigue
  trabajando. Hay que consultar el estado, no esperar la respuesta.
- Las macros de calibración se niegan a ejecutarse si `idle_timeout` está en
  `Printing`. Hay que esperar a `Ready` antes de lanzarlas.
- Si el `z_offset` cambia más de ~0,5 mm sin haber tocado boquilla ni soporte,
  **es un error de medida**, no un dato. Repetir antes de encadenar
  `DELTA_CALIBRATION`, que propaga el fallo a toda la geometría.
