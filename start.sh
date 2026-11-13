#!/usr/bin/env bash
# First boot: download the 3 model files to the persistent volume (/workspace),
# link them into ComfyUI, then launch ComfyUI on port 8188.
# Later boots: files already exist -> download is skipped, ComfyUI starts fast.
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/opt/ComfyUI}"
MODELS_DIR="${WORKSPACE_DIR:-/workspace}/models"
PORT="${COMFY_PORT:-8188}"
QUANT="${GGUF_QUANT:-Q4_K_M}"

case "$QUANT" in
  Q3_K_M|Q4_K_S|Q4_K_M|Q5_K_M|Q6_K|Q8_0) ;;
  *) echo "[start] ERROR: GGUF_QUANT=$QUANT is not a valid quant. Use Q3_K_M / Q4_K_S / Q4_K_M / Q5_K_M / Q6_K / Q8_0" >&2; exit 1 ;;
esac

DIT_FILE="qwen_image_2.1_turbo_${QUANT}.gguf"
DIT_URL="https://huggingface.co/Abiray/Qwen-Image-2.1-viggle-4-steps-turbo-GGUF/resolve/main/${DIT_FILE}"
ENC_FILE="qwen3vl_8b_int8_convrot.safetensors"
ENC_URL="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/${ENC_FILE}"
VAE_FILE="qwen_image_2.1_vae_bf16.safetensors"
VAE_URL="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/${VAE_FILE}"

mkdir -p \
  "$MODELS_DIR/diffusion_models" \
  "$MODELS_DIR/text_encoders" \
  "$MODELS_DIR/vae" \
  "$COMFY_DIR/user/default/workflows"

# Public, ungated repos -> HF_TOKEN is optional. Pass it only if you set one.
AUTH=()
if [ -n "${HF_TOKEN:-}" ]; then AUTH=(-H "Authorization: Bearer ${HF_TOKEN}"); fi

download() { # $1=url  $2=dest — skip when a non-empty file is already there
  if [ -s "$2" ]; then
    echo "[start] already downloaded: $2"
  else
    echo "[start] downloading: $1 -> $2"
    wget -c --tries=5 --timeout=60 "${AUTH[@]}" -O "$2.part" "$1" && mv "$2.part" "$2"
  fi
}

download "$DIT_URL" "$MODELS_DIR/diffusion_models/$DIT_FILE"
download "$ENC_URL" "$MODELS_DIR/text_encoders/$ENC_FILE"
download "$VAE_URL" "$MODELS_DIR/vae/$VAE_FILE"

# Link the volume models into ComfyUI's model folders (idempotent)
for sub in diffusion_models text_encoders vae; do
  for f in "$MODELS_DIR/$sub"/*; do
    [ -e "$f" ] || continue
    ln -sf "$f" "$COMFY_DIR/models/$sub/$(basename "$f")"
  done
done

# Keep input/output on the volume so results survive a pod restart
mkdir -p "${WORKSPACE_DIR:-/workspace}/input" "${WORKSPACE_DIR:-/workspace}/output"
for d in input output; do
  if [ -d "$COMFY_DIR/$d" ] && [ ! -L "$COMFY_DIR/$d" ]; then rm -rf "$COMFY_DIR/$d"; fi
  ln -sfn "${WORKSPACE_DIR:-/workspace}/$d" "$COMFY_DIR/$d"
done  
# Refresh the bundled workflows and point their GGUF loader at the quant
# this boot actually downloaded (GGUF_QUANT), whatever the image default was.
cp -f /opt/workflows/*.json "$COMFY_DIR/user/default/workflows/" 2>/dev/null || true
sed -i "s/qwen_image_2.1_turbo_[A-Za-z0-9_]*\.gguf/${DIT_FILE}/g" \
  "$COMFY_DIR/user/default/workflows/"*.json 2>/dev/null || true

# VRAM flag: auto = --lowvram at <=16 GB VRAM, normal at >16 GB.
# Set LOWVRAM=on / off to force it.
EXTRA_ARGS=""
case "${LOWVRAM:-auto}" in
  on|1) EXTRA_ARGS="--lowvram" ;;
  off|0) EXTRA_ARGS="" ;;
  *)
    VRAM_MIB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0)"
    VRAM_MIB="${VRAM_MIB//[^0-9]/}"
    if [ -n "$VRAM_MIB" ] && [ "$VRAM_MIB" -le 16384 ]; then EXTRA_ARGS="--lowvram"; fi
    echo "[start] GPU VRAM: ${VRAM_MIB:-unknown} MiB (extra args: '${EXTRA_ARGS}')"
    ;;
esac

echo "[start] Launching ComfyUI on port $PORT (quant: $QUANT)"
cd "$COMFY_DIR"
# shellcheck disable=SC2086
exec python main.py --listen 0.0.0.0 --port "$PORT" $EXTRA_ARGS
