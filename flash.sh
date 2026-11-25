#!/usr/bin/env bash
# Flashea la FRDM-MCXW72 desde el host con LinkServer (NXP).
# Funciona con el firmware CMSIS-DAP de fábrica del MCU-Link.
set -euo pipefail

LINKSERVER="${LINKSERVER:-/usr/local/LinkServer/LinkServer}"
DEVICE="${DEVICE:-MCXW727C:FRDM-MCXW72}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEX="${1:-${PROJECT_DIR}/zephyrproject/build-mcxw72/zephyr/zephyr.hex}"

if [[ -f /.dockerenv ]]; then
  echo "Estás dentro del contenedor: flash.sh debe ejecutarse en el HOST." >&2
  echo "Sal con 'exit' y vuelve a lanzar ./flash.sh desde la terminal del host." >&2
  exit 1
fi

if [[ ! -x "$LINKSERVER" ]]; then
  echo "No se encuentra LinkServer en $LINKSERVER" >&2
  echo "Instálalo con el MCUXpresso Installer o define LINKSERVER=/ruta/a/LinkServer" >&2
  exit 1
fi

if [[ ! -f "$HEX" ]]; then
  echo "No existe $HEX" >&2
  echo "Compila primero con: west build -p always -b frdm_mcxw72 -d build-mcxw72 <app> -- -DCONFIG_BUILD_OUTPUT_HEX=y" >&2
  exit 1
fi

exec "$LINKSERVER" flash "$DEVICE" load "$HEX"
