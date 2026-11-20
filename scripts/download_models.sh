#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Format: "REPO_ID|REMOTE_PATH|TARGET_SUBDIR"
MODELS=(
    # --- Wan 2.2 (FP8 Scaled + LightX2V 4-Step Rank-64 LoRAs + LightTAE) ---
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors|diffusion_models"
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors|diffusion_models"
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|diffusion_models"
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|diffusion_models"
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|text_encoders"
    "Comfy-Org/Wan_2.2_ComfyUI_Repackaged|split_files/vae/wan_2.1_vae.safetensors|vae"
    "lightx2v/Wan2.2-Distill-Loras|wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors|loras"
    "lightx2v/Wan2.2-Distill-Loras|wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors|loras"
    "lightx2v/Wan2.2-Distill-Loras|wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors|loras"
    "lightx2v/Wan2.2-Distill-Loras|wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors|loras"
    "lightx2v/Autoencoders|lighttaew2_1.pth|vae_approx"

    # --- MiniMax-H3 + LightX2V Turbo (4-Step v1.3 ComfyUI LoRA + LightVAE) ---
    "Comfy-Org/MiniMax-H3|diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors|diffusion_models"
    "Comfy-Org/MiniMax-H3|text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors|text_encoders"
    "Comfy-Org/MiniMax-H3|vae/minimax_h3_video_vae_fp16.safetensors|vae"
    "Comfy-Org/MiniMax-H3|vae/minimax_h3_audio_vae_fp32.safetensors|vae"
    "lightx2v/Minimax-h3-Turbo|minimax_h3_fl2v_turbo_4step_v1.3_768p_comfyui_bf16.safetensors|loras"
    "lightx2v/LightVAE|lightvae-lite-h3-decoder.safetensors|vae/LightVAE"
    "lightx2v/LightVAE|lightvae-lite-h3-encoder.safetensors|vae/LightVAE"

    # --- LTX-2 19B (FP8 Checkpoint + Distilled 8-Step LoRA + Gemma 3 12B Text Encoder + 2x Spatial Upscaler) ---
    "Lightricks/LTX-2|ltx-2-19b-dev-fp8.safetensors|checkpoints"
    "Lightricks/LTX-2|ltx-2-19b-distilled-lora-384.safetensors|loras"
    "Lightricks/LTX-2|ltx-2-spatial-upscaler-x2-1.0.safetensors|latent_upscale_models"
    "Comfy-Org/ltx-2|split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors|text_encoders"
)

if [ ! -x "$VENV_DIR/bin/python" ] || [ ! -d "$COMFYUI_DIR" ]; then
    printf '[!] ComfyUI or its Python environment is missing. Run %s/install.sh first.\n' "$INSTALL_DIR" >&2
    exit 1
fi

if [ ! -x "$VENV_DIR/bin/hf" ]; then
    printf '[*] Installing the Hugging Face CLI in the ComfyUI Python environment.\n'
    "$VENV_DIR/bin/python" -m pip install --upgrade 'huggingface_hub[cli]'
fi

if [ ! -x "$VENV_DIR/bin/hf" ]; then
    printf '[!] Hugging Face CLI was not found at %s/bin/hf after installation.\n' "$VENV_DIR" >&2
    exit 1
fi

models_dir="$COMFYUI_DIR/models"
mkdir -p "$models_dir"
staging_dir="$(mktemp -d "$models_dir/.hf-download.XXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT

export HF_TOKEN
failures=0

for model in "${MODELS[@]}"; do
    IFS='|' read -r repo_id remote_path target_subdir extra <<< "$model"
    if [ -z "$repo_id" ] || [ -z "$remote_path" ] || [ -z "$target_subdir" ] || [ -n "${extra:-}" ] \
        || [[ ! "$repo_id" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] \
        || [[ "$remote_path" = /* || "/$remote_path/" = *"/../"* ]] \
        || [[ "$target_subdir" = /* || "/$target_subdir/" = *"/../"* ]]; then
        printf '[!] Invalid model entry: %s\n' "$model" >&2
        failures=$((failures + 1))
        continue
    fi

    filename="${remote_path##*/}"
    downloaded_file="$staging_dir/$remote_path"
    destination_dir="$models_dir/$target_subdir"
    destination="$destination_dir/$filename"

    if [ -s "$destination" ]; then
        printf '[*] Already exists, skipping: %s\n' "$destination"
        continue
    fi

    printf '[*] Downloading %s from %s\n' "$filename" "$repo_id"
    if ! "$VENV_DIR/bin/hf" download "$repo_id" "$remote_path" --local-dir "$staging_dir"; then
        printf '[!] Failed to download %s from %s.\n' "$remote_path" "$repo_id" >&2
        failures=$((failures + 1))
        continue
    fi

    if [ ! -s "$downloaded_file" ]; then
        printf '[!] Hugging Face CLI did not create the expected file: %s\n' "$downloaded_file" >&2
        failures=$((failures + 1))
        continue
    fi

    mkdir -p "$destination_dir"
    if ! mv -f -- "$downloaded_file" "$destination"; then
        printf '[!] Failed to move %s to %s.\n' "$filename" "$destination" >&2
        failures=$((failures + 1))
    fi
done

if [ "$failures" -ne 0 ]; then
    printf '[!] Finished with %s failure(s).\n' "$failures" >&2
    exit 1
fi

printf '\nModel downloads complete.\n'
