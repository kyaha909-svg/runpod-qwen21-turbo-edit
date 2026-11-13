#!/usr/bin/env bash
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
cat > user/default/workflows/qwen21_turbo_edit.json <<'WORKFLOW_EOF'
{
  "id": "qwen21-turbo-edit-1ref",
  "revision": 0,
  "last_node_id": 10,
  "last_link_id": 10,
  "nodes": [
    {
      "id": 1,
      "type": "UnetLoaderGGUF",
      "pos": [
        40,
        40
      ],
      "size": [
        330,
        60
      ],
      "order": 0,
      "inputs": [],
      "outputs": [
        {
          "name": "MODEL",
          "type": "MODEL",
          "links": [
            1
          ]
        }
      ],
      "widgets_values": [
        "qwen_image_2.1_turbo_Q4_K_M.gguf"
      ],
      "title": "Unet Loader (GGUF) — Turbo",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "UnetLoaderGGUF"
      }
    },
    {
      "id": 2,
      "type": "CLIPLoader",
      "pos": [
        40,
        140
      ],
      "size": [
        330,
        110
      ],
      "order": 1,
      "inputs": [],
      "outputs": [
        {
          "name": "CLIP",
          "type": "CLIP",
          "links": [
            2
          ]
        }
      ],
      "widgets_values": [
        "qwen3vl_8b_int8_convrot.safetensors",
        "qwen_image",
        "default"
      ],
      "title": "Load CLIP — Qwen3-VL 8B int8",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "CLIPLoader"
      }
    },
    {
      "id": 3,
      "type": "VAELoader",
      "pos": [
        40,
        290
      ],
      "size": [
        330,
        60
      ],
      "order": 2,
      "inputs": [],
      "outputs": [
        {
          "name": "VAE",
          "type": "VAE",
          "links": [
            3,
            4
          ]
        }
      ],
      "widgets_values": [
        "qwen_image_2.1_vae_bf16.safetensors"
      ],
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "VAELoader"
      }
    },
    {
      "id": 4,
      "type": "LoadImage",
      "pos": [
        40,
        400
      ],
      "size": [
        330,
        380
      ],
      "order": 3,
      "inputs": [],
      "outputs": [
        {
          "name": "IMAGE",
          "type": "IMAGE",
          "links": [
            5
          ]
        },
        {
          "name": "MASK",
          "type": "MASK",
          "links": null
        }
      ],
      "widgets_values": [
        "example.png",
        "image"
      ],
      "title": "Load Image — edit target (image_1)",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "LoadImage"
      }
    },
    {
      "id": 5,
      "type": "TextEncodeQwenImage21",
      "pos": [
        430,
        40
      ],
      "size": [
        440,
        340
      ],
      "order": 5,
      "inputs": [
        {
          "name": "clip",
          "type": "CLIP",
          "link": 2
        },
        {
          "name": "vae",
          "type": "VAE",
          "link": 3
        },
        {
          "name": "images.image_1",
          "shape": 7,
          "type": "IMAGE",
          "link": 5
        }
      ],
      "outputs": [
        {
          "name": "positive",
          "type": "CONDITIONING",
          "links": [
            6
          ]
        },
        {
          "name": "negative",
          "type": "CONDITIONING",
          "links": [
            7
          ]
        },
        {
          "name": "latent",
          "type": "LATENT",
          "links": [
            8
          ]
        }
      ],
      "widgets_values": [
        "Change the background to a rainy cyberpunk street at night, keeping the person's face, pose and clothes unchanged.",
        "",
        1024
      ],
      "title": "Text Encode Qwen Image 2.1 — edit instruction",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "TextEncodeQwenImage21"
      }
    },
    {
      "id": 6,
      "type": "KSampler",
      "pos": [
        930,
        40
      ],
      "size": [
        330,
        300
      ],
      "order": 6,
      "inputs": [
        {
          "name": "model",
          "type": "MODEL",
          "link": 1
        },
        {
          "name": "positive",
          "type": "CONDITIONING",
          "link": 6
        },
        {
          "name": "negative",
          "type": "CONDITIONING",
          "link": 7
        },
        {
          "name": "latent_image",
          "type": "LATENT",
          "link": 8
        }
      ],
      "outputs": [
        {
          "name": "LATENT",
          "type": "LATENT",
          "links": [
            9
          ]
        }
      ],
      "widgets_values": [
        42,
        "randomize",
        4,
        1.0,
        "euler",
        "simple",
        1.0
      ],
      "title": "KSampler — 4 steps / cfg 1.0 (fixed)",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "KSampler"
      }
    },
    {
      "id": 7,
      "type": "VAEDecode",
      "pos": [
        1330,
        40
      ],
      "size": [
        210,
        60
      ],
      "order": 7,
      "inputs": [
        {
          "name": "samples",
          "type": "LATENT",
          "link": 9
        },
        {
          "name": "vae",
          "type": "VAE",
          "link": 4
        }
      ],
      "outputs": [
        {
          "name": "IMAGE",
          "type": "IMAGE",
          "links": [
            10
          ]
        }
      ],
      "widgets_values": [],
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "VAEDecode"
      }
    },
    {
      "id": 8,
      "type": "SaveImage",
      "pos": [
        1330,
        150
      ],
      "size": [
        330,
        300
      ],
      "order": 8,
      "inputs": [
        {
          "name": "images",
          "type": "IMAGE",
          "link": 10
        }
      ],
      "outputs": [],
      "widgets_values": [
        "qwen21_turbo_edit"
      ],
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "SaveImage"
      }
    },
    {
      "id": 10,
      "type": "MarkdownNote",
      "pos": [
        430,
        430
      ],
      "size": [
        440,
        260
      ],
      "order": 9,
      "inputs": [],
      "outputs": [],
      "widgets_values": [
        "## Qwen-Image-2.1 Viggle Turbo — Image Edit\n1. LoadImage に編集したい画像を入れる（これが image_1 = 編集対象）\n2. TextEncodeQwenImage21 の prompt に編集指示を書く（参照画像は <image1> <image2> と呼ぶ）\n3. KSampler は固定: steps 4 / cfg 1.0 / euler / simple / denoise 1.0（上げると焼けます）\n4. resolution 1024 = 総画素数の目安。元画像の比率は維持される。0 で元サイズ\n出力は /workspace/output に保存されます。"
      ],
      "title": "使い方",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "MarkdownNote"
      }
    }
  ],
  "links": [
    [
      1,
      1,
      0,
      6,
      0,
      "MODEL"
    ],
    [
      2,
      2,
      0,
      5,
      0,
      "CLIP"
    ],
    [
      3,
      3,
      0,
      5,
      1,
      "VAE"
    ],
    [
      4,
      3,
      0,
      7,
      1,
      "VAE"
    ],
    [
      5,
      4,
      0,
      5,
      2,
      "IMAGE"
    ],
    [
      6,
      5,
      0,
      6,
      1,
      "CONDITIONING"
    ],
    [
      7,
      5,
      1,
      6,
      2,
      "CONDITIONING"
    ],
    [
      8,
      5,
      2,
      6,
      3,
      "LATENT"
    ],
    [
      9,
      6,
      0,
      7,
      0,
      "LATENT"
    ],
    [
      10,
      7,
      0,
      8,
      0,
      "IMAGE"
    ]
  ],
  "groups": [],
  "config": {},
  "extra": {
    "ds": {
      "scale": 0.8,
      "offset": [
        0,
        0
      ]
    }
  },
  "version": 0.4
}
WORKFLOW_EOF
cat > user/default/workflows/qwen21_turbo_edit_2ref.json <<'WORKFLOW_EOF'
{
  "id": "qwen21-turbo-edit-2ref",
  "revision": 0,
  "last_node_id": 10,
  "last_link_id": 11,
  "nodes": [
    {
      "id": 1,
      "type": "UnetLoaderGGUF",
      "pos": [
        40,
        40
      ],
      "size": [
        330,
        60
      ],
      "order": 0,
      "inputs": [],
      "outputs": [
        {
          "name": "MODEL",
          "type": "MODEL",
          "links": [
            1
          ]
        }
      ],
      "widgets_values": [
        "qwen_image_2.1_turbo_Q4_K_M.gguf"
      ],
      "title": "Unet Loader (GGUF) — Turbo",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "UnetLoaderGGUF"
      }
    },
    {
      "id": 2,
      "type": "CLIPLoader",
      "pos": [
        40,
        140
      ],
      "size": [
        330,
        110
      ],
      "order": 1,
      "inputs": [],
      "outputs": [
        {
          "name": "CLIP",
          "type": "CLIP",
          "links": [
            2
          ]
        }
      ],
      "widgets_values": [
        "qwen3vl_8b_int8_convrot.safetensors",
        "qwen_image",
        "default"
      ],
      "title": "Load CLIP — Qwen3-VL 8B int8",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "CLIPLoader"
      }
    },
    {
      "id": 3,
      "type": "VAELoader",
      "pos": [
        40,
        290
      ],
      "size": [
        330,
        60
      ],
      "order": 2,
      "inputs": [],
      "outputs": [
        {
          "name": "VAE",
          "type": "VAE",
          "links": [
            3,
            4
          ]
        }
      ],
      "widgets_values": [
        "qwen_image_2.1_vae_bf16.safetensors"
      ],
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "VAELoader"
      }
    },
    {
      "id": 4,
      "type": "LoadImage",
      "pos": [
        40,
        400
      ],
      "size": [
        330,
        380
      ],
      "order": 3,
      "inputs": [],
      "outputs": [
        {
          "name": "IMAGE",
          "type": "IMAGE",
          "links": [
            5
          ]
        },
        {
          "name": "MASK",
          "type": "MASK",
          "links": null
        }
      ],
      "widgets_values": [
        "example.png",
        "image"
      ],
      "title": "Load Image — edit target (image_1)",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "LoadImage"
      }
    },
    {
      "id": 5,
      "type": "TextEncodeQwenImage21",
      "pos": [
        430,
        40
      ],
      "size": [
        440,
        340
      ],
      "order": 5,
      "inputs": [
        {
          "name": "clip",
          "type": "CLIP",
          "link": 2
        },
        {
          "name": "vae",
          "type": "VAE",
          "link": 3
        },
        {
          "name": "images.image_1",
          "shape": 7,
          "type": "IMAGE",
          "link": 5
        },
        {
          "name": "images.image_2",
          "shape": 7,
          "type": "IMAGE",
          "link": 6
        }
      ],
      "outputs": [
        {
          "name": "positive",
          "type": "CONDITIONING",
          "links": [
            7
          ]
        },
        {
          "name": "negative",
          "type": "CONDITIONING",
          "links": [
            8
          ]
        },
        {
          "name": "latent",
          "type": "LATENT",
          "links": [
            9
          ]
        }
      ],
      "widgets_values": [
        "Change the background to a rainy cyberpunk street at night, keeping the person's face, pose and clothes unchanged.",
        "",
        1024
      ],
      "title": "Text Encode Qwen Image 2.1 — edit instruction",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "TextEncodeQwenImage21"
      }
    },
    {
      "id": 6,
      "type": "KSampler",
      "pos": [
        930,
        40
      ],
      "size": [
        330,
        300
      ],
      "order": 6,
      "inputs": [
        {
          "name": "model",
          "type": "MODEL",
          "link": 1
        },
        {
          "name": "positive",
          "type": "CONDITIONING",
          "link": 7
        },
        {
          "name": "negative",
          "type": "CONDITIONING",
          "link": 8
        },
        {
          "name": "latent_image",
          "type": "LATENT",
          "link": 9
        }
      ],
      "outputs": [
        {
          "name": "LATENT",
          "type": "LATENT",
          "links": [
            10
          ]
        }
      ],
      "widgets_values": [
        42,
        "randomize",
        4,
        1.0,
        "euler",
        "simple",
        1.0
      ],
      "title": "KSampler — 4 steps / cfg 1.0 (fixed)",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "KSampler"
      }
    },
    {
      "id": 7,
      "type": "VAEDecode",
      "pos": [
        1330,
        40
      ],
      "size": [
        210,
        60
      ],
      "order": 7,
      "inputs": [
        {
          "name": "samples",
          "type": "LATENT",
          "link": 10
        },
        {
          "name": "vae",
          "type": "VAE",
          "link": 4
        }
      ],
      "outputs": [
        {
          "name": "IMAGE",
          "type": "IMAGE",
          "links": [
            11
          ]
        }
      ],
      "widgets_values": [],
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "VAEDecode"
      }
    },
    {
      "id": 8,
      "type": "SaveImage",
      "pos": [
        1330,
        150
      ],
      "size": [
        330,
        300
      ],
      "order": 8,
      "inputs": [
        {
          "name": "images",
          "type": "IMAGE",
          "link": 11
        }
      ],
      "outputs": [],
      "widgets_values": [
        "qwen21_turbo_edit"
      ],
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "SaveImage"
      }
    },
    {
      "id": 9,
      "type": "LoadImage",
      "pos": [
        40,
        830
      ],
      "size": [
        330,
        380
      ],
      "order": 4,
      "inputs": [],
      "outputs": [
        {
          "name": "IMAGE",
          "type": "IMAGE",
          "links": [
            6
          ]
        },
        {
          "name": "MASK",
          "type": "MASK",
          "links": null
        }
      ],
      "widgets_values": [
        "example_ref.png",
        "image"
      ],
      "title": "Load Image — reference (image_2)",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "LoadImage"
      }
    },
    {
      "id": 10,
      "type": "MarkdownNote",
      "pos": [
        430,
        430
      ],
      "size": [
        440,
        260
      ],
      "order": 9,
      "inputs": [],
      "outputs": [],
      "widgets_values": [
        "## Qwen-Image-2.1 Viggle Turbo — Image Edit\n1. LoadImage に編集したい画像を入れる（これが image_1 = 編集対象）\n2. TextEncodeQwenImage21 の prompt に編集指示を書く（参照画像は <image1> <image2> と呼ぶ）\n3. KSampler は固定: steps 4 / cfg 1.0 / euler / simple / denoise 1.0（上げると焼けます）\n4. resolution 1024 = 総画素数の目安。元画像の比率は維持される。0 で元サイズ\n出力は /workspace/output に保存されます。"
      ],
      "title": "使い方",
      "flags": {},
      "mode": 0,
      "properties": {
        "Node name for S&R": "MarkdownNote"
      }
    }
  ],
  "links": [
    [
      1,
      1,
      0,
      6,
      0,
      "MODEL"
    ],
    [
      2,
      2,
      0,
      5,
      0,
      "CLIP"
    ],
    [
      3,
      3,
      0,
      5,
      1,
      "VAE"
    ],
    [
      4,
      3,
      0,
      7,
      1,
      "VAE"
    ],
    [
      5,
      4,
      0,
      5,
      2,
      "IMAGE"
    ],
    [
      6,
      9,
      0,
      5,
      3,
      "IMAGE"
    ],
    [
      7,
      5,
      0,
      6,
      1,
      "CONDITIONING"
    ],
    [
      8,
      5,
      1,
      6,
      2,
      "CONDITIONING"
    ],
    [
      9,
      5,
      2,
      6,
      3,
      "LATENT"
    ],
    [
      10,
      6,
      0,
      7,
      0,
      "LATENT"
    ],
    [
      11,
      7,
      0,
      8,
      0,
      "IMAGE"
    ]
  ],
  "groups": [],
  "config": {},
  "extra": {
    "ds": {
      "scale": 0.8,
      "offset": [
        0,
        0
      ]
    }
  },
  "version": 0.4
}
WORKFLOW_EOF

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
