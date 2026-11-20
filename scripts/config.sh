#!/usr/bin/env bash

# Change these values to match your pod and GPU.
INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$INSTALL_DIR/venv"
COMFYUI_DIR="$INSTALL_DIR/ComfyUI"
SAGE_ATTENTION=true # Set to false to use ComfyUI's default attention.
COMFYUI_PORT=8188
HF_TOKEN="${HF_TOKEN:-}"
