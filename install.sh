#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/config.sh"

install_args=()
case "$GPU_TYPE" in
    nvidia) install_args+=(--nvidia) ;;
    amd) install_args+=(--amd) ;;
    cpu) install_args+=(--cpu) ;;
    auto) ;;
    *)
        printf '[!] GPU_TYPE must be nvidia, amd, cpu, or auto (got: %s).\n' "$GPU_TYPE" >&2
        exit 1
        ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    printf '[!] python3 is required.\n' >&2
    exit 1
fi

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
"$VENV_DIR/bin/python" -m pip install --upgrade pip comfy-cli

if [ -d "$COMFYUI_DIR" ]; then
    install_args+=(--restore)
fi

"$VENV_DIR/bin/comfy" \
    --workspace="$COMFYUI_DIR" \
    --skip-prompt \
    install \
    "${install_args[@]}"

printf '\nComfyUI installation complete.\n'
printf 'Start it with: %s/scripts/run_comfyui.sh\n' "$INSTALL_DIR"
printf 'Expose port %s in your pod to access the web interface.\n' "$COMFYUI_PORT"
