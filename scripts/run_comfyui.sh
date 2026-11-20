#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

if [ ! -x "$VENV_DIR/bin/comfy" ]; then
    printf '[!] ComfyUI is not installed. Run %s/install.sh first.\n' "$INSTALL_DIR" >&2
    exit 1
fi

if [ ! -d "$COMFYUI_DIR" ]; then
    printf '[!] ComfyUI workspace not found at %s. Run %s/install.sh first.\n' "$COMFYUI_DIR" "$INSTALL_DIR" >&2
    exit 1
fi

source "$VENV_DIR/bin/activate"
cd "$COMFYUI_DIR"

launch_args=(--listen 0.0.0.0 --port "$COMFYUI_PORT" --preview-method auto)
if [ "$GPU_TYPE" = cpu ]; then
    launch_args+=(--cpu)
fi

exec comfy --workspace="$COMFYUI_DIR" launch -- "${launch_args[@]}"
