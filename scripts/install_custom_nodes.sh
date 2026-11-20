#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Add or remove repository URLs here.
# https://www.floyo.ai/all-comfyui-nodes
repositories=(
    "https://github.com/Lyonir/ComfyUI-Lyonir-Studio"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
    "https://github.com/uczensokratesa/ComfyUI-RTX-Video-Suite"
    "https://github.com/Deno2026/comfyui-deno-custom-nodes.git"
    "https://github.com/TRI3D-LC/tri3d-comfyui-nodes"
    "https://github.com/Comfy-Org/ComfyUI-Manager"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/yolain/ComfyUI-Easy-Sam3"
    "https://github.com/kijai/ComfyUI-SCAIL-Pose"
    "https://gitlab.com/pixaroma/ComfyUI-Pixaroma.git"
    "https://github.com/kijai/ComfyUI-Florence2"
    "https://github.com/EY4O/ComfyUI-Model-Librarian"
    "https://github.com/Madiator2011Work/ComfyUI-RunpodDirect"
    "https://github.com/eniewold/ComfyUI-Subworkflow"
    "https://github.com/BennyDaBall930/comfyui_hyperflow_int8_nodes"
    "https://github.com/Extraltodeus/Skimmed_CFG"
    "https://github.com/ussoewwin/ComfyUI-QwenImageLoraLoader"
    "https://github.com/tritant/ComfyUI_Custom_Switch"
    "https://github.com/uczensokratesa/ComfyUI-RTX-Video-Suite"
    "https://github.com/lrzjason/ComfyUI-EditUtils"
    "https://github.com/StartHua/Comfyui_joytag"
    "https://github.com/FloyoAI/LTX2EasyPrompt-LD"
    "https://github.com/princepainter/ComfyUI-PainterQwenImageEdit"
    "https://github.com/1038lab/ComfyUI-RMBG"
)

if ! command -v git >/dev/null 2>&1; then
    printf '[!] git is required.\n' >&2
    exit 1
fi

if [ ! -x "$VENV_DIR/bin/python" ] || [ ! -d "$COMFYUI_DIR" ]; then
    printf '[!] ComfyUI or its Python environment is missing. Run %s/install.sh first.\n' "$INSTALL_DIR" >&2
    exit 1
fi

custom_nodes_dir="$COMFYUI_DIR/custom_nodes"
mkdir -p "$custom_nodes_dir"
failures=0

for repository in "${repositories[@]}"; do
    name="${repository##*/}"
    name="${name%.git}"
    node_dir="$custom_nodes_dir/$name"

    if [ -e "$node_dir" ]; then
        if [ ! -d "$node_dir" ]; then
            printf '[!] Cannot install %s: %s is not a directory.\n' "$name" "$node_dir" >&2
            failures=$((failures + 1))
            continue
        fi
        printf '[*] Keeping existing node: %s\n' "$name"
    else
        printf '[*] Cloning %s\n' "$name"
        if ! git clone -- "$repository" "$node_dir"; then
            printf '[!] Failed to clone %s.\n' "$name" >&2
            failures=$((failures + 1))
            continue
        fi
    fi

    if [ -f "$node_dir/requirements.txt" ]; then
        printf '[*] Installing requirements for %s\n' "$name"
        if ! "$VENV_DIR/bin/python" -m pip install -r "$node_dir/requirements.txt"; then
            printf '[!] Failed to install requirements for %s.\n' "$name" >&2
            failures=$((failures + 1))
        fi
    else
        printf '[*] No requirements.txt for %s; skipping dependencies.\n' "$name"
    fi
done

if [ "$failures" -ne 0 ]; then
    printf '[!] Finished with %s failure(s).\n' "$failures" >&2
    exit 1
fi

printf '\nCustom node installation complete.\n'
