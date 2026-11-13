"""Generate setup-on-pod.sh: one-command setup for an official RunPod
ComfyUI pod (installs ComfyUI-GGUF, downloads the 3 model files, installs
the edit workflows, restarts ComfyUI). Workflow JSONs are embedded as
heredocs so the script is fully self-contained.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

HEADER = r"""#!/usr/bin/env bash
# Qwen-Image-2.1 Viggle Turbo (GGUF) image-edit setup for an official
# RunPod ComfyUI pod (runpod/comfyui image). Run it in the pod's web
# terminal or Jupyter terminal:
#   bash setup-on-pod.sh
# It installs ComfyUI-GGUF, downloads ~14.2 GB of models, installs the
# edit workflows, and restarts ComfyUI on port 8188.
set -euo pipefail

QUANT="${GGUF_QUANT:-Q4_K_M}"
case "$QUANT" in Q3_K_M|Q4_K_S|Q4_K_M|Q5_K_M|Q6_K|Q8_0) ;; *)
  echo "ERROR: bad GGUF_QUANT=$QUANT" >&2; exit 1;; esac
DIT_FILE="qwen_image_2.1_turbo_${QUANT}.gguf"
DIT_URL="https://huggingface.co/Abiray/Qwen-Image-2.1-viggle-4-steps-turbo-GGUF/resolve/main/${DIT_FILE}"
ENC_FILE="qwen3vl_8b_int8_convrot.safetensors"
ENC_URL="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/text_encoders/${ENC_FILE}"
VAE_FILE="qwen_image_2.1_vae_bf16.safetensors"
VAE_URL="https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/${VAE_FILE}"

echo "== Finding ComfyUI =="
COMFY_DIR=""
for d in /workspace/runpod-slim/ComfyUI /workspace/ComfyUI /opt/ComfyUI "$HOME/ComfyUI"; do
  if [ -f "$d/main.py" ]; then COMFY_DIR="$d"; break; fi
done
if [ -z "$COMFY_DIR" ]; then
  COMFY_DIR="$(find /workspace -maxdepth 4 -name main.py -path '*ComfyUI*' 2>/dev/null | head -n1 | xargs -r dirname)"
fi
[ -n "$COMFY_DIR" ] && [ -f "$COMFY_DIR/main.py" ] || { echo "ERROR: ComfyUI not found under /workspace" >&2; exit 1; }
echo "ComfyUI: $COMFY_DIR"
cd "$COMFY_DIR"

echo "== Python environment =="
PY="python3"
for v in .venv-cu128 .venv-cu130 .venv-cu132 .venv venv; do
  if [ -x "$v/bin/python" ]; then PY="$COMFY_DIR/$v/bin/python"; break; fi
done
echo "python: $PY ($($PY --version 2>&1))"

echo "== ComfyUI-GGUF =="
if [ ! -d custom_nodes/ComfyUI-GGUF ]; then
  git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git custom_nodes/ComfyUI-GGUF
fi
"$PY" -m pip install -q -r custom_nodes/ComfyUI-GGUF/requirements.txt
"$PY" -m pip install -q -U "gguf>=0.13.0"
grep -q "TextEncodeQwenImage21" comfy_extras/nodes_qwen.py \
  || { echo "ERROR: this ComfyUI is too old for Qwen-Image 2.1 (no TextEncodeQwenImage21)" >&2; exit 1; }

echo "== Models (skips files already downloaded) =="
dl() { # url dest
  if [ -s "$2" ]; then echo "have: $2"; else
    echo "downloading: $1"; wget -c --tries=5 -O "$2.part" "$1" && mv "$2.part" "$2"; fi
}
mkdir -p models/diffusion_models models/text_encoders models/vae
dl "$DIT_URL" "models/diffusion_models/$DIT_FILE"
dl "$ENC_URL" "models/text_encoders/$ENC_FILE"
dl "$VAE_URL" "models/vae/$VAE_FILE"
ls -lh models/diffusion_models/ models/text_encoders/ models/vae/

echo "== Workflows =="
mkdir -p user/default/workflows
"""

FOOTER = r"""
echo "== Restarting ComfyUI =="
pkill -f "main.py.*8188" 2>/dev/null || true
sleep 3
EXTRA=""
VRAM_MIB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0)"
VRAM_MIB="${VRAM_MIB//[^0-9]/}"
if [ -n "$VRAM_MIB" ] && [ "$VRAM_MIB" -le 16384 ]; then EXTRA="--lowvram"; fi
nohup "$PY" main.py --listen 0.0.0.0 --port 8188 $EXTRA > /workspace/comfyui-qwen.log 2>&1 &
sleep 20
tail -n 20 /workspace/comfyui-qwen.log || true
echo
echo "DONE. Open the pod's HTTP service for port 8188, then:"
echo "  Workflow menu -> qwen21_turbo_edit (1 reference image)"
echo "  KSampler stays at steps 4 / cfg 1.0 / euler / simple."
"""


def heredoc(filename: str, content: str) -> str:
    assert "WORKFLOW_EOF" not in content
    return (f"cat > user/default/workflows/{filename} <<'WORKFLOW_EOF'\n"
            f"{content}\nWORKFLOW_EOF\n")


def main():
    parts = [HEADER]
    for name in ("qwen21_turbo_edit.json", "qwen21_turbo_edit_2ref.json"):
        with open(os.path.join(HERE, "workflows", name)) as f:
            parts.append(heredoc(name, f.read().rstrip("\n")))
    parts.append(FOOTER)
    out = os.path.join(HERE, "setup-on-pod.sh")
    with open(out, "w") as f:
        f.write("".join(parts))
    os.chmod(out, 0o755)
    print("wrote", out)


if __name__ == "__main__":
    main()
