# Acceso remoto y nombres del taller

Cómo se llegan a controlar las tres impresoras desde fuera de la red local, y
por qué el acceso se monta en capas.

---

## Las máquinas

| Nombre | Qué es | Papel |
|---|---|---|
| **flora** | V400 · Speeder Pad | **La principal.** Restaurada y configurada el 2026‑09‑15. Es la referencia: toda la configuración probada sale de aquí |
| **v400-2** | V400 · misma configuración | Se unifica con Flora en un solo pad (ver abajo) |
| **sr-1** | FLSUN SR · pad propio | Independiente |

Las tres están en el mismo taller. El tercer pad queda de repuesto — y después
de lo del 15 de septiembre, tener un pad de recambio no es un lujo.

Los nombres no son decorativos: con Tailscale se convierten en direcciones
reales, así que `ssh flora` funciona desde cualquier parte del mundo.

---

## Las cuatro capas de acceso

La lección del 15 de septiembre es que **una sola vía de entrada no basta**.
Aquel día el pad se quedó sin red y no había ninguna otra forma de entrar:
hubo que reinstalar entero y se perdió una tarde.

| Capa | Para qué | Depende de |
|---|---|---|
| 1 · WiFi local | Uso diario | El router de casa |
| 2 · **Tailscale** | Desde cualquier sitio, SSH incluido | Que el pad tenga internet |
| 3 · **USB‑Ethernet** | Cable al router o directo al PC | Nada más que el cable |
| 4 · **USB de rescate** | Cuando no hay ninguna red | Nada |

Las cuatro son independientes. Para quedarte fuera tendrían que fallar todas a
la vez.

---

## 1 · Tailscale

```bash
sudo bash Flsun-v400/scripts/tailscale-setup.sh flora
```

Al final muestra una URL: ábrela en el navegador para autorizar la máquina en
tu cuenta. Sin ese paso no queda conectada.

Repite en las otras con `v400-2` y `sr-1`.

Después, desde cualquier equipo que tenga Tailscale:

```bash
ssh pi@flora          # SSH remoto, sin abrir puertos en el router
http://flora          # Mainsail
```

### Por qué es seguro

Crea su propia interfaz (`tailscale0`) y **no toca `wlan0`**. No puede dejarte
fuera como hizo NetworkManager: es de las pocas cosas de red que se pueden
ejecutar por SSH sin red de seguridad. Aun así, el script comprueba al final
que la IP local siga en pie y la restaura si hiciera falta.

### Lo que resuelve, además de lo evidente

**La IP deja de importar.** El día 15 se perdió el pad porque cambió de
dirección al reconectar. Con Tailscale la dirección es fija y el nombre
también.

---

## 2 · USB‑Ethernet

```bash
sudo bash Flsun-v400/scripts/soporte-ethernet.sh
```

Deja el pad listo para coger red en cuanto enchufes un adaptador USB‑Ethernet.
Dos usos:

- **Al router:** más estable que el WiFi para impresiones largas
- **Directo al PC:** vía de rescate sin depender de ninguna red

Para el caso del cable directo, la configuración incluye
`LinkLocalAddressing=ipv4`: aunque no haya servidor DHCP al otro lado, ambos
extremos cogen una dirección `169.254.x.x` y se ven entre sí. Sin eso, un cable
directo al portátil no daría nada.

También arregla un detalle que pasó desapercibido: `systemd-networkd` estaba en
`enabled-runtime`, es decir, activo pero **sin sobrevivir a un reinicio**.

---

## 3 · El teclado: por qué no es una vía

`Ctrl+Alt+F2` **congela el pad**. No es un fallo de configuración: KlipperScreen
ocupa el framebuffer y el driver gráfico del Allwinner no cambia de consola.
Hay que reiniciar para recuperar la pantalla.

Se puede intentar habilitar un `getty` en otra terminal, pero no hay garantía de
que funcione. Con las capas 2, 3 y 4 cubiertas, el teclado deja de hacer falta.

---

## 4 · Unificar las dos V400 en un pad

Ambas comparten configuración y están juntas, así que tiene sentido que las
lleve el mismo pad — que es, de hecho, para lo que la Speeder Pad trae soporte
multi‑instancia de fábrica (`klipper-1/2/3`, que el aprovisionamiento retira
para dejar una sola).

**Ventaja directa:** los gcodes quedan en un único sitio. Cargas una vez y
envías a cualquiera de las dos, sin sincronizar nada.

**Lo que hay que tener en cuenta:**

- Las dos impresoras van por USB al mismo pad. Cables de pocos metros o un hub
- Si el pad cae, caen las dos
- La pantalla muestra una impresora cada vez
- Cada instancia necesita su puerto: Moonraker en 7125 y 7126

**Pendiente de montar.** Requiere volver a meter una segunda instancia sobre la
instalación actual, con su `printer_data` propio y su entrada en nginx. Se hace
después de que el acceso remoto esté probado, no antes: es más invasivo y
conviene tener las cuatro capas de entrada funcionando por si acaso.
