#!/usr/bin/env bash
# Flashea la FRDM-MCXW71 o FRDM-MCXW72 desde el host con LinkServer (NXP).
#
# Uso:
#   BOARD=frdm_mcxw72 ./flash.sh [ruta/a/zephyr.hex]   (por defecto)
#   BOARD=frdm_mcxw71 ./flash.sh [ruta/a/zephyr.hex]
set -euo pipefail

BOARD="${BOARD:-frdm_mcxw72}"
LINKSERVER="${LINKSERVER:-/usr/local/LinkServer/LinkServer}"

case "$BOARD" in
  frdm_mcxw72) DEFAULT_DEVICE="MCXW727C:FRDM-MCXW72"; BUILD_DIR="build-mcxw72" ;;
  frdm_mcxw71) DEFAULT_DEVICE="MCXW716CxxxA:FRDM-MCXW71"; BUILD_DIR="build-mcxw71" ;;
  *)
    echo "BOARD desconocida: $BOARD (usa frdm_mcxw71 o frdm_mcxw72)" >&2
    exit 1
    ;;
esac
DEVICE="${DEVICE:-$DEFAULT_DEVICE}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEX="${1:-${PROJECT_DIR}/zephyrproject/${BUILD_DIR}/zephyr/zephyr.hex}"

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
  echo "Compila primero con: west build -p always -b $BOARD -d $BUILD_DIR <app> -- -DCONFIG_BUILD_OUTPUT_HEX=y" >&2
  exit 1
fi

# Comprueba que el HEX se compiló para la placa elegida (lee el .config del build).
CONFIG_FILE="$(dirname "$HEX")/.config"
if [[ -f "$CONFIG_FILE" ]]; then
  BUILT_FOR="$(sed -n 's/^CONFIG_BOARD="\(.*\)"$/\1/p' "$CONFIG_FILE")"
  if [[ -n "$BUILT_FOR" && "$BUILT_FOR" != "$BOARD" ]]; then
    echo "El HEX fue compilado para '$BUILT_FOR', pero BOARD='$BOARD'." >&2
    echo "Usa BOARD=$BUILT_FOR o recompila para $BOARD." >&2
    exit 1
  fi
else
  echo "Aviso: no se encontró $CONFIG_FILE; no se puede verificar para qué placa es el HEX." >&2
fi

exec "$LINKSERVER" flash "$DEVICE" load "$HEX"
