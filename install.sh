#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/config.sh"

# Fix pip cache warning (cache lives on /workspace)
mkdir -p /workspace/.cache/pip
chmod -R 777 /workspace/.cache || true

# Build deps for torch/CUDA extensions (needed for SageAttention build and many nodes)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    build-essential \
    ninja-build \
    python3-dev \
    git

install_args=(--nvidia)

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

# -----------------------------------------------------------------------------
# ComfyUI-Manager setup (custom_nodes)
# -----------------------------------------------------------------------------
printf '[*] Installing ComfyUI-Manager...\n'
MANAGER_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Manager"
mkdir -p "$COMFYUI_DIR/custom_nodes"

if [ -d "$MANAGER_DIR/.git" ]; then
    git -C "$MANAGER_DIR" pull --ff-only
elif [ -d "$MANAGER_DIR" ]; then
    # Directory exists but isn't a git repo; keep it and clone fresh next to it
    printf '[!] %s exists but is not a git repo; skipping git pull.\n' "$MANAGER_DIR" >&2
else
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$MANAGER_DIR"
fi

# -----------------------------------------------------------------------------
# SageAttention install (unconditional)
# -----------------------------------------------------------------------------
printf '[*] Building SageAttention for the NVIDIA GPU.\n'
"$VENV_DIR/bin/python" -m pip install "setuptools>=62,<75" "wheel>=0.38,<0.44" "packaging>=21,<24" ninja "triton>=3.0.0"
"$VENV_DIR/bin/python" -m pip install --no-build-isolation --no-deps --force-reinstall --no-cache-dir \
    'git+https://github.com/thu-ml/SageAttention.git@eb615cf6cf4d221338033340ee2de1c37fbdba4a'
"$VENV_DIR/bin/python" -c 'from sageattention import sageattn, _qattn_sm80'

printf '\nComfyUI installation complete.\n'
printf 'Start services with: %s/scripts/run_services.sh\n' "$INSTALL_DIR"
printf 'Expose port %s in your pod to access the web interface.\n' "$COMFYUI_PORT"
