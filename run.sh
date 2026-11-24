#!/usr/bin/env bash
# Arranca el contenedor del curso con el workspace de Zephyr persistido en el host.
set -euo pipefail

IMAGE="${IMAGE:-mi-zephyr-curso}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${PROJECT_DIR}/zephyrproject"

DOCKER_ARGS=(
  --rm -it
  --entrypoint bash
  -v "${PROJECT_DIR}:/workdir"
  -w /workdir
)

# Modo B: pasar los dispositivos USB para poder flashear desde el contenedor.
if [[ "${USB_PASSTHROUGH:-0}" == "1" ]]; then
  DOCKER_ARGS+=(-v /dev/bus/usb:/dev/bus/usb --device-cgroup-rule='c 189:* rmw')
  for dev in /dev/ttyACM*; do
    [[ -e "$dev" ]] && DOCKER_ARGS+=(--device "$dev")
  done
fi

exec docker run "${DOCKER_ARGS[@]}" "$IMAGE"
