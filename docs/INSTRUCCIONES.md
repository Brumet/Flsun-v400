# Conectar el Speeder Pad a una red WiFi nueva

Datos del equipo:

| | |
|---|---|
| Hostname | `speeder-pad` |
| Usuario | `pi` |
| Sistema | Ubuntu 20.04 (armhf) |
| Puerto de red | Sí (adaptador Realtek RTL8152) |

---

## PLAN A — Portátil conectado directamente al pad por cable (recomendado)

No hace falta router ni configurar nada en casa del cliente.

### 1. Conectar

Cable Ethernet normal del portátil al puerto de red del pad. Los adaptadores
modernos cruzan las señales solos, no hace falta cable cruzado.

### 2. Entrar por SSH

```bash
ssh pi@speeder-pad.local
```

Si eso no resuelve, asignar IPs manualmente. **En el portátil:**

```bash
# ver el nombre de la interfaz (algo tipo enp3s0, eth0...)
ip -br link

sudo ip addr add 192.168.50.1/24 dev NOMBRE_INTERFAZ
sudo ip link set NOMBRE_INTERFAZ up
```

Y buscar el pad en ese rango:

```bash
sudo nmap -sn 192.168.50.0/24        # si hay nmap
# o simplemente probar:
ping 192.168.50.2
```

> Si el pad no coge IP en ese rango, es que espera DHCP. Alternativa rápida:
> compartir la conexión del portátil (`Configuración de red` → el perfil cableado
> → IPv4 → método **Compartido con otros equipos**). Así el portátil actúa de
> router y le da IP al pad automáticamente.

### 3. Copiar el script y ejecutarlo

Desde el portátil:

```bash
scp conectar-wifi.sh pi@speeder-pad.local:/home/pi/
ssh pi@speeder-pad.local
```

Ya dentro del pad:

```bash
# Primero mirar, sin cambiar nada:
sudo bash /home/pi/conectar-wifi.sh --diagnostico

# Luego conectar:
sudo bash /home/pi/conectar-wifi.sh "NombreDeLaRed" "LaContrasena"
```

El script detecta solo cómo está gestionada la red, hace copia de seguridad de
lo que toca, aplica la configuración y verifica que haya IP. Al terminar muestra
la dirección del pad.

### 4. Quitar el cable

El WiFi queda guardado y se reconecta solo en cada arranque.

---

## PLAN B — Compartir internet desde un móvil Android por USB

Sirve cuando no hay cable ni router accesible.

1. Conectar el móvil al pad con cable USB
2. En el móvil: *Ajustes → Conexiones → Conexión compartida → **Anclaje USB***
3. El pad recibe internet al instante (aparece como interfaz `usb0`)
4. En el móvil, ver la lista de dispositivos conectados para saber la IP del pad
5. Con una app tipo **JuiceSSH** o **Termux**, entrar por SSH y ejecutar el script

---

## PLAN C — Dejar la impresora por cable, sin WiFi

Si llega un cable de red hasta donde está la impresora, es la mejor opción:

- Funciona sin configurar nada
- Es **más estable que el WiFi** para imprimir: sin cortes por interferencia
  a mitad de una pieza larga

Basta con conectar el cable del router al pad.

---

## Para que el panel de red de la pantalla funcione (opcional)

El mensaje *"Failed to detect NetworkManager service"* aparece porque
NetworkManager no está instalado. Sin él, el WiFi no se puede cambiar desde la
pantalla táctil.

**Hacer esto solo con el pad ya conectado a internet**, y preferiblemente con el
cable Ethernet puesto para no quedarse sin acceso si algo falla:

```bash
sudo apt-get install network-manager -y
```

Parecerá que se cuelga en `Processing triggers for systemd` y dará un error de
conexión abortada. **Es normal**, la documentación de Guilouz lo advierte.

```bash
sudo mkdir -p /etc/NetworkManager/conf.d
sudo nano /etc/NetworkManager/conf.d/any-user.conf
```

Contenido del archivo (permite que KlipperScreen gestione la red sin ser root):

```
[main]
auth-polkit=false
```

Guardar con `Ctrl+X`, `Y`, `Enter`. Después:

```bash
sudo systemctl -q disable dhcpcd; sudo systemctl -q stop dhcpcd
sudo systemctl enable NetworkManager
sudo systemctl -q --no-block start NetworkManager
nmcli device wifi connect "NombreDeLaRed" password "LaContrasena"
```

A partir de ahí el panel de red de la pantalla funciona y el cliente puede
cambiar de red él mismo.

---

## Si algo sale mal

El script hace copia de seguridad antes de tocar nada, con el nombre original
más `.bak-<fecha>`. Para restaurar:

```bash
ls /etc/netplan/*.bak-* /etc/wpa_supplicant/*.bak-*
sudo cp /etc/netplan/ARCHIVO.bak-XXXX /etc/netplan/ARCHIVO
sudo netplan apply
```

## Notas sobre la impresora

- La línea `[include adxlmcu.cfg]` en `printer.cfg` está **comentada**.
  Solo debe descomentarse con el acelerómetro KUSBA conectado por USB;
  si se activa sin la placa, Klipper no arranca.
- La cámara tarda ~15 segundos en aparecer tras encender: es intencionado,
  un retardo que evita que arranque antes de que el USB esté listo.
