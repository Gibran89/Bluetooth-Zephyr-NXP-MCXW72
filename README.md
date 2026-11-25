# Curso de Bluetooth con Zephyr y NXP FRDM-MCXW72

Entorno de desarrollo reproducible basado en Docker para el curso de Bluetooth Low Energy
sobre Zephyr RTOS y las placas **NXP FRDM-MCXW72** y **FRDM-MCXW71**.

> **Dos placas, un mismo proyecto.** Los pasos 1 a 6 son comunes. Lo que cambia
> entre placas es el nombre de la board de west (`frdm_mcxw72` / `frdm_mcxw71`),
> el directorio de build y, sobre todo, el procedimiento de la NBU (sección 7).
> `flash.sh` elige la placa con la variable `BOARD` (por defecto `frdm_mcxw72`).
> **No mezcles los firmwares NBU de una placa con la otra.**

---

## Requisitos

- Docker instalado y funcionando sin `sudo` (`docker run hello-world`)
- ~10 GB de espacio libre en disco
- Placa NXP FRDM-MCXW72 o FRDM-MCXW71 con cable USB-C
- **LinkServer** instalado en el host (paso 5.1)

---

## 1. Construir la imagen

```bash
git clone <url-del-repo> Bluetooth-Zephyr-NXP-MCXW72
cd Bluetooth-Zephyr-NXP-MCXW72

docker build \
  --build-arg UID=$(id -u) \
  --build-arg GID=$(id -g) \
  --build-arg USERNAME=$(id -un) \
  -t mi-zephyr-curso .
```

Los `--build-arg` hacen que el usuario dentro del contenedor tenga tu mismo UID/GID,
de modo que los archivos creados en el volumen te pertenezcan (sin problemas de permisos).

Verifica:

```bash
docker run --rm --entrypoint west mi-zephyr-curso --version
```

## 2. Entrar al contenedor

```bash
./run.sh
```

El script monta la carpeta del proyecto en `/workdir` dentro del contenedor.
Todo lo que escribas ahí persiste en tu host.

## 3. Inicializar el workspace de Zephyr (solo la primera vez)

Dentro del contenedor, ejecuta cada comando en este orden:

```bash
west init -m https://github.com/zephyrproject-rtos/zephyr --mr v4.4.2 /workdir/zephyrproject
```

Inicializa el workspace en `/workdir/zephyrproject` y clona Zephyr como
repositorio manifiesto. Su archivo `west.yml` especifica los módulos y sus
revisiones. `--mr v4.4.2` fija la versión de Zephyr usada y probada en este
proyecto. Este comando se ejecuta solo al crear el workspace por primera vez.

```bash
cd /workdir/zephyrproject
```

Cambia a la raíz del workspace para que West encuentre su configuración y el
manifiesto.

```bash
west update --narrow -o=--depth=1
```

Descarga las revisiones de los módulos indicadas por el manifiesto, incluido
`hal_nxp`, necesario para la FRDM-MCXW72. `--narrow` evita descargar referencias
Git innecesarias y `-o=--depth=1` crea clones superficiales para ahorrar espacio.
La contrapartida es que esos clones no contienen el historial completo.

```bash
west zephyr-export
```

Registra la instalación de Zephyr para que CMake y otras herramientas externas
puedan localizarla.

Si `/workdir/zephyrproject` ya existe y está inicializado, no repitas `west init`.
Entra al directorio y ejecuta `west update` cuando necesites sincronizar los
módulos con el manifiesto.

> Solo se hace una vez: la carpeta `zephyrproject/` queda en tu host y no se borra
> al salir del contenedor.

**No hace falta `pip install -r requirements.txt`:** la imagen ya trae un virtualenv en
`/opt/python/venv` con las dependencias de Zephyr preinstaladas (`pyelftools`, `pykwalify`,
`anytree`, `intelhex`, etc.). Ejecutar `pip install --user` ahí falla con
*"User site-packages are not visible in this virtualenv"*, y es inofensivo ignorarlo.

**Por qué `--narrow -o=--depth=1`:** `west update` clona los ~70 módulos del manifiesto
con todo su historial. Estas dos opciones reducen mucho la descarga (el tamaño
final del workspace medido aquí es ~6.5 GB):

- `--narrow` — no descarga todos los tags de cada repositorio
- `-o=--depth=1` — clon superficial: solo el commit que el manifiesto necesita

Es la misma estrategia que usa la CI de Zephyr. La contrapartida es que no tendrás
historial de git dentro de los módulos, algo irrelevante para el curso.

**Sobre la versión:** `v4.4.2` está fijada a propósito. La imagen `zephyr-build:v0.29.4`
incluye el **Zephyr SDK 1.0.1**, que es el que corresponde a la serie 4.3/4.4. Usar una
release más antigua (p. ej. v4.1) provoca un error de verificación de versión del toolchain.
Si cambias el tag de la imagen base, ajusta también esta versión.

## 4. Build de validación

```bash
cd /workdir/zephyrproject
west build -p always -b frdm_mcxw72 -d build-mcxw72 zephyr/samples/basic/blinky -- -DCONFIG_BUILD_OUTPUT_HEX=y
```

Si termina con `Memory region ... Used Size`, tu entorno está listo.

Si tienes la **FRDM-MCXW71**, usa la board `frdm_mcxw71` y su propio directorio:

```bash
west build -p always -b frdm_mcxw71 -d build-mcxw71 zephyr/samples/basic/blinky -- -DCONFIG_BUILD_OUTPUT_HEX=y
```

Cada placa tiene su directorio de build (`build-mcxw72`, `build-mcxw71`), independientes entre sí.
`-p always` limpia el directorio indicado antes de compilar; no lo uses sobre un
build que quieras conservar.

`-DCONFIG_BUILD_OUTPUT_HEX=y` es necesario: por defecto esta placa solo genera
`zephyr.bin` y `zephyr.elf`, y LinkServer necesita el `.hex`.

## 5. Flashear la placa

> **⚠️ A partir de aquí sales del contenedor.** Los pasos 3 y 4 se hacen dentro
> del contenedor (`./run.sh`). Antes de empezar el paso 5, escribe `exit` para
> volver a la terminal del **host**. Todo el paso 5 (instalar LinkServer y
> `./flash.sh`) se ejecuta en el host, porque LinkServer está instalado allí y
> el contenedor no tiene acceso a la placa. Si ejecutas `./flash.sh` dentro del
> contenedor verás `No se encuentra LinkServer`.
>
> Flujo típico: compilar en el contenedor → `exit` → flashear en el host.

La FRDM-MCXW72 integra un depurador **MCU-Link**. El script usa **LinkServer** y
requiere que la sonda tenga firmware compatible con LinkServer/CMSIS-DAP. La
configuración de Zephyr para esta placa usa J-Link como runner predeterminado;
comprueba el firmware instalado antes de elegir la herramienta. Si es necesario
cambiarlo, consulta la documentación de la placa y sus instrucciones para JP5.

### 5.1 Instalar LinkServer (solo una vez)

1. Descarga el **MCUXpresso Installer** desde el sitio de NXP (requiere cuenta gratuita).
2. Ejecútalo como root:
   ```bash
   chmod +x MCUXpressoInstaller.deb.bin
   sudo ./MCUXpressoInstaller.deb.bin
   /home/$USER/MCUXpressoInstaller/MCUXpressoInstaller
   ```
3. En la sección **Debug Probes Software** marca únicamente **LinkServer** y pulsa *Install*.

> No marques "Zephyr Developer", "Zephyr SDK" ni "Arm GNU Toolchain": ya están en la
> imagen Docker y ocuparían varios GB duplicados en el host.

Queda instalado en `/usr/local/LinkServer/`. Verifica que detecta la placa:

```bash
/usr/local/LinkServer/LinkServer probes
```

Comprueba que aparece la sonda MCU-Link y sus capacidades de depuración y consola.

### 5.2 Flashear

Desde el **host** (no desde el contenedor):

```bash
./flash.sh
```

Usa `zephyrproject/build-mcxw72/zephyr/zephyr.hex` por defecto y selecciona
`MCXW727C:FRDM-MCXW72`. Para la FRDM-MCXW71, indica la placa con `BOARD`
(usa `build-mcxw71` y el dispositivo `MCXW716CxxxA:FRDM-MCXW71`):

```bash
BOARD=frdm_mcxw71 ./flash.sh
```

También acepta una ruta:

```bash
./flash.sh ruta/a/otro.hex
```

El script comprueba que el HEX fue compilado para la placa indicada en `BOARD`
(lee `CONFIG_BOARD` del `.config` junto al HEX) y se niega a flashear si no
coincide. Se pueden ajustar las variables `LINKSERVER` y `DEVICE` si tu instalación lo requiere.

Termina con `Finished writing Flash successfully`.

## 6. Consola serie

Conecta el USB de la placa a J14 y abre la consola a 115200 baudios:

```bash
# en el host
picocom -b 115200 /dev/ttyACM0
```

También se puede usar Minicom:

```bash
minicom -D /dev/ttyACM0 -b 115200
```

Si con Minicom no ves salida, desactiva el control de flujo por hardware
(`Ctrl+A`, `O`, "Serial port setup", opción F).

Pulsa RESET para ver los mensajes de arranque. Para salir de picocom, pulsa
`Ctrl+A` y después `Ctrl+X`; para salir de Minicom, `Ctrl+A` y después `X`. El
nombre del dispositivo serie puede variar; verifica cuál corresponde a la placa
y cierra la consola antes de usar `blhost`.

## 7. Bluetooth y firmware NBU

> Las secciones 7.1 a 7.3 describen la **FRDM-MCXW72**. Si tienes la
> **FRDM-MCXW71**, ve directamente a la sección 7.4: el procedimiento de NBU es
> distinto.

La MCXW72 ejecuta la aplicación Zephyr en el núcleo principal y el controlador
Bluetooth en el subsistema NBU. Para obtener los archivos de NXP, revisa sus
licencias y, dentro del contenedor, ejecuta:

```bash
cd /workdir/zephyrproject
west blobs -l 'mcxw72/mcxw72_nbu_ble_all_hosted[.]bin$' fetch hal_nxp
```

Este comando descarga únicamente la imagen BLE hospedada
`mcxw72_nbu_ble_all_hosted.bin` en `modules/hal/nxp/zephyr/blobs/mcxw72/`.
Para descargar todos los blobs del módulo se puede usar `west blobs fetch hal_nxp`.
No reutilices una imagen de MCXW71: la elección de firmware depende del uso y
debe coincidir con la versión del workspace y la configuración de la placa.

La documentación de Zephyr para la placa describe el uso de `blhost`, el modo
ISP y la programación separada de la NBU. **El procedimiento documentado incluye
comandos de borrado de flash**: antes de ejecutarlos, verifica qué contiene la
placa, haz las copias necesarias y confirma el dispositivo y la imagen. Consulta
`zephyr/boards/nxp/frdm_mcxw72/doc/index.rst` dentro del workspace. No se debe
asumir que la NBU ya está preparada ni que la compilación del host la programa.

### 7.1 Respaldo y preparación de la NBU

La actualización de la NBU sustituye el firmware de radio existente. En esta
placa se usó la imagen del workspace Zephyr 4.4.2, `blhost` de SPSDK 3.11.0
incluido en `mi-zephyr-curso` y la sonda MCU-Link con LinkServer. La conexión del
depurador puede detener o reiniciar la placa y modificar la RAM.

Antes de actualizar, considera respaldar la NBU. Por ejemplo, desde el host y
con la placa conectada por MCU-Link, crea un directorio privado nuevo y guarda
los 512 KiB de la región NBU:

```bash
umask 077
BACKUP_DIR=$(mktemp -d "$HOME/mcxw72-nbu-backup-XXXXXXXX")
/usr/local/LinkServer/LinkServer flash -u none MCXW727C:FRDM-MCXW72 dump 0x48800000 0x80000 "$BACKUP_DIR/nbu-original.bin"
/usr/local/LinkServer/LinkServer flash -u none MCXW727C:FRDM-MCXW72 verify -a 0x48800000 "$BACKUP_DIR/nbu-original.bin"
sha256sum "$BACKUP_DIR/nbu-original.bin"
```

Conserva el directorio privado: puede contener datos de la placa. Esta copia solo
cubre la región NBU, no la flash principal, IFR ni fusibles; verificar la lectura
no garantiza que la restauración funcione. La copia realizada durante esta
prueba se guardó fuera del repositorio y coincidió con la flash; su
restauración no se probó. No subas el respaldo al repositorio.

Para entrar en modo ISP, cierra el programa de consola, desconecta todas las
fuentes de alimentación y conecta un cable USB-C de datos al puerto MCU-Link J10
mientras mantienes pulsado SW3. Suelta SW3 después de conectar. Identifica el
puerto serie en el host, por ejemplo con `ls -l /dev/serial/by-id/`; en la prueba
fue `/dev/ttyACM0`. Ajusta el puerto en los comandos siguientes si cambia.

Desde el host, comprueba la conexión sin borrar ni escribir flash:

```bash
docker run --rm --device /dev/ttyACM0 --entrypoint blhost mi-zephyr-curso -p /dev/ttyACM0 get-property 1
```

La placa probada respondió `Success` y `Current Version = K3.1.0`. La versión es
del bootloader, no identifica el firmware NBU instalado.

**Los siguientes comandos son destructivos.** El ejemplo BLE de la
[nota de aplicación NXP AN14802](https://www.nxp.com/docs/en/application-note/AN14802.pdf)
describe el borrado del ID `2` como borrado de NBU y después programa la imagen
en `0x48800000`. No hemos confirmado todos los efectos sobre datos de fábrica o
regiones protegidas; revisa la documentación, preserva los datos necesarios y
confirma placa, puerto e imagen antes de continuar. No se usó `flash-erase-all 0`.

Con la placa en ISP, desde la raíz del proyecto en el host, manteniendo la
alimentación conectada y tras comprobar el respaldo y la comunicación:

```bash
docker run --rm --device /dev/ttyACM0 --entrypoint blhost mi-zephyr-curso -p /dev/ttyACM0 flash-erase-all 2
```

Solo si el borrado terminó con `Success`, programa la imagen BLE del workspace:

```bash
docker run --rm --device /dev/ttyACM0 -v "$PWD/zephyrproject/modules/hal/nxp/zephyr/blobs/mcxw72:/firmware:ro" --entrypoint blhost mi-zephyr-curso -p /dev/ttyACM0 write-memory 0x48800000 /firmware/mcxw72_nbu_ble_all_hosted.bin
```

La escritura probada respondió `Success` con 282804 bytes. Para verificarla,
desde la raíz del proyecto en el host:

```bash
/usr/local/LinkServer/LinkServer flash -u none MCXW727C:FRDM-MCXW72 verify -a 0x48800000 zephyrproject/modules/hal/nxp/zephyr/blobs/mcxw72/mcxw72_nbu_ble_all_hosted.bin
```

El resultado esperado es `File matches flash` y `verify succeeded`. La
verificación puede detener o reiniciar la placa. Para salir de ISP, suelta SW3 y
pulsa RESET sin mantener SW3; si hace falta, desconecta y vuelve a conectar la
alimentación sin presionarlo.

### 7.2 Prueba BLE con Heart Rate

Compila el ejemplo oficial en un directorio independiente, dentro del
contenedor:

```bash
cd /workdir/zephyrproject
west build -p always -b frdm_mcxw72 -d build-mcxw72-hr zephyr/samples/bluetooth/peripheral_hr -- -DCONFIG_BUILD_OUTPUT_HEX=y
```

Desde la raíz del proyecto en el host, flashea la aplicación principal:

```bash
./flash.sh zephyrproject/build-mcxw72-hr/zephyr/zephyr.hex
```

Esto reemplaza la aplicación principal, pero no programa la NBU. Abre Minicom y
pulsa RESET; con la NBU actualizada, en la placa probada aparecieron:

```text
Bluetooth initialized
Starting Legacy Advertising (connectable and scannable)
Advertising successfully started
```

Busca `Zephyr Heartrate Sensor` con nRF Connect o NXP IoT Toolbox y conecta.
El servicio Heart Rate ofrece valores simulados; activa las notificaciones de
Heart Rate Measurement para recibirlos. En nuestra prueba se observó la conexión
y, al activar las notificaciones de Heart Rate Measurement, la consola mostró
`HRS notifications enabled` y nRF Connect recibió valores simulados que
cambiaban cada segundo, lo que confirma que el servicio funciona. Si el
teléfono conservaba un emparejamiento anterior (`BONDED` en nRF Connect), elimina
el vínculo antes de conectar. Para volver a `blinky`, ejecuta `./flash.sh` sin
argumentos.

### 7.3 Ejemplo beacon

Para compilar el beacon sin reemplazar `blinky`:

```bash
cd /workdir/zephyrproject
west build -p always -b frdm_mcxw72 -d build-mcxw72-beacon zephyr/samples/bluetooth/beacon -- -DCONFIG_BUILD_OUTPUT_HEX=y
```

Desde el host, una vez preparada la NBU y confirmada la placa, se puede indicar
el HEX del ejemplo explícitamente con
`./flash.sh zephyrproject/build-mcxw72-beacon/zephyr/zephyr.hex`. Compilar el
ejemplo no verifica la radio: hay que comprobar el advertising en hardware.

### 7.4 FRDM-MCXW71: NBU y prueba BLE

La MCXW71 también necesita una imagen NBU para Bluetooth, pero el procedimiento
difiere del de la MCXW72:

| | MCXW72 | MCXW71 |
|---|---|---|
| Archivo | `mcxw72_nbu_ble_all_hosted.bin` | `mcxw71_nbu_ble.sb3` |
| `blhost` | `flash-erase-all 2` y `write-memory 0x48800000 ...` | `receive-sb-file` (sin borrado ni dirección) |
| Respaldo/verificación con LinkServer | sí (región NBU a `0x48800000`) | **no**: LinkServer solo ve la flash principal |

Dentro del contenedor, descarga solo el blob BLE de la MCXW71 (las variantes
`15_4_dyn` añaden 802.15.4 y no hacen falta para el curso):

```bash
cd /workdir/zephyrproject
west blobs -l 'mcxw71/mcxw71_nbu_ble[.]sb3$' fetch hal_nxp
```

**La escritura de la NBU reemplaza el firmware de radio y no se puede respaldar
con LinkServer**, así que no podrás restaurar el firmware original desde este
flujo. Para entrar en modo ISP: desconecta la placa de toda alimentación, mantén
pulsado SW3 mientras conectas el USB y suéltalo. (La documentación de Zephyr
menciona "MCXW72" en ese paso por una errata; verifica el modo con `blhost`.)
Comprueba la comunicación sin escribir nada:

```bash
docker run --rm --device /dev/ttyACM0 --entrypoint blhost mi-zephyr-curso -p /dev/ttyACM0 get-property 1
```

En la placa probada respondió `Success` y `Current Version = K3.1.0`. Después,
desde la raíz del proyecto en el host, con la placa en ISP:

```bash
docker run --rm --device /dev/ttyACM0 -v "$PWD/zephyrproject/modules/hal/nxp/zephyr/blobs/mcxw71:/firmware:ro" --entrypoint blhost mi-zephyr-curso -p /dev/ttyACM0 -- receive-sb-file /firmware/mcxw71_nbu_ble.sb3
```

La escritura probada respondió `Success`. Sal de ISP pulsando RESET sin mantener
SW3. Compila y flashea el Heart Rate para la MCXW71:

```bash
# contenedor
west build -p always -b frdm_mcxw71 -d build-mcxw71-hr zephyr/samples/bluetooth/peripheral_hr -- -DCONFIG_BUILD_OUTPUT_HEX=y
# host
BOARD=frdm_mcxw71 ./flash.sh zephyrproject/build-mcxw71-hr/zephyr/zephyr.hex
```

Como la NBU no se puede verificar con LinkServer, la prueba es la consola serie:
con la NBU correcta aparecen `Bluetooth initialized` y `Advertising successfully
started`. En la placa probada se conectó con nRF Connect y la consola mostró
`HRS notifications enabled`.

---

## Estructura del repositorio

```
Bluetooth-Zephyr-NXP-MCXW72/
├── Dockerfile          # Imagen de desarrollo (Zephyr SDK + toolchain)
├── run.sh              # Arranque del contenedor
├── flash.sh            # Flasheo con LinkServer, BOARD=frdm_mcxw71|frdm_mcxw72 (en el host)
├── .gitignore
├── apps/               # Ubicación prevista para ejercicios propios (actualmente vacía)
└── zephyrproject/      # Workspace west (NO versionado, ~6.5 GB medidos)
```

**Dónde se ejecuta cada cosa:**

| Host | Contenedor |
|---|---|
| `docker build`, `./run.sh`, `./flash.sh`, `picocom`, `blhost` (vía `docker run`), LinkServer | `west init`, `west update`, `west build`, `west blobs fetch` |

---

## Contenido del curso

| # | Tema | Sample base |
|---|------|-------------|
| 1 | Advertising y beacons | `samples/bluetooth/beacon` |
| 2 | GATT: servicios y características | `samples/bluetooth/peripheral_hr` |
| 3 | Servicio GATT propio con notificaciones | `apps/` |
| 4 | Rol central: escaneo y conexión | `samples/bluetooth/central` |
| 5 | Seguridad: pairing y bonding | `samples/bluetooth/peripheral_sc_only` |
| 6 | Proyecto final | `apps/` |

---

## Problemas frecuentes

**`failed to read dockerfile`** — estás en la carpeta equivocada. Ejecuta `docker build` desde
el directorio que contiene el `Dockerfile`.

**Mensajes de Openbox / Xlib / VNC al arrancar** — son del entrypoint de la imagen base, no son
errores. `run.sh` ya los evita usando `--entrypoint bash`.

**Permisos denegados en archivos del volumen** — reconstruye la imagen pasando tus
`UID`/`GID` reales como en el paso 1.

**`west update` se queda sin espacio** — el workspace ocupa ~6.5 GB (medido con
`du -sh zephyrproject`, sin contar los builds) y cada build añade entre 25 y 55 MB.

**Error de versión del toolchain / SDK** — la versión de Zephyr y la del Zephyr SDK de la imagen
deben ser compatibles. Comprueba cuál trae la imagen con:

```bash
docker run --rm --entrypoint cat mi-zephyr-curso /opt/toolchains/zephyr-sdk-*/sdk_version
```

**`Can not perform a '--user' install. User site-packages are not visible in this virtualenv`**
— la imagen usa un virtualenv con las dependencias ya instaladas. Omite ese paso.

**`./run.sh: line N: exec: docker: not found`** — estás ejecutando `run.sh` *dentro* del
contenedor. Sal con `exit` y lánzalo desde el host.

**`No existe .../zephyr.hex`** — compila con `-- -DCONFIG_BUILD_OUTPUT_HEX=y`.

**`BLE Controller initialization failed` / `HCI driver is not ready` / `err -19`**
— el controlador no se inicializó. En la placa probada el error desapareció tras
programar la imagen NBU BLE del mismo workspace. El mensaje por sí solo no
demuestra que el firmware sea la causa: revisa la configuración y las versiones
antes de reprogramar. Preserva los datos necesarios y revisa el procedimiento de
la sección 7.1 antes de borrar o escribir la NBU.

**El ejemplo BLE compila pero no anuncia** — revisa los mensajes de la consola y
comprueba el firmware NBU específico de MCXW72 y su compatibilidad.

**LinkServer no encuentra la sonda** — comprueba que la placa está conectada:

```bash
lsusb | grep 1fc9
/usr/local/LinkServer/LinkServer probes
```
