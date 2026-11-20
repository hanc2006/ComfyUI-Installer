#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/config.sh"

install_args=(--nvidia)

case "$SAGE_ATTENTION" in
    true|false) ;;
    *)
        printf '[!] SAGE_ATTENTION must be true or false (got: %s).\n' "$SAGE_ATTENTION" >&2
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

if [ "$SAGE_ATTENTION" = true ]; then
    printf '[*] Building SageAttention for the NVIDIA GPU.\n'
    "$VENV_DIR/bin/python" -m pip install "setuptools>=62,<75" "wheel>=0.38,<0.44" "packaging>=21,<24" ninja "triton>=3.0.0"
    "$VENV_DIR/bin/python" -m pip install --no-build-isolation --no-deps --force-reinstall --no-cache-dir \
        'git+https://github.com/thu-ml/SageAttention.git@eb615cf6cf4d221338033340ee2de1c37fbdba4a'
    "$VENV_DIR/bin/python" -c 'from sageattention import sageattn, _qattn_sm80'
fi

printf '\nComfyUI installation complete.\n'
printf 'Start it with: %s/scripts/run_comfyui.sh\n' "$INSTALL_DIR"
printf 'Expose port %s in your pod to access the web interface.\n' "$COMFYUI_PORT"
