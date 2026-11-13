# Qwen-Image-2.1 Viggle Turbo (GGUF) — Image Edit — RunPod Pod image
# Base: official RunPod PyTorch image (CUDA 12.8 / torch 2.8 / Ubuntu 24.04).
# Models are NOT baked into the image: start.sh downloads them to the
# persistent /workspace volume on first boot (~14.2 GB) and reuses them after.
FROM runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    COMFY_DIR=/opt/ComfyUI \
    WORKSPACE_DIR=/workspace \
    GGUF_QUANT=Q6_K \
    LOWVRAM=auto \
    COMFY_PORT=8188

WORKDIR /opt

# System tools ComfyUI / start.sh need
RUN apt-get update && apt-get install -y --no-install-recommends \
      git wget curl aria2 ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# ComfyUI (latest master — Qwen-Image 2.1 nodes TextEncodeQwenImage21 /
# QwenImage21Cache only exist in recent builds) + ComfyUI-GGUF (city96, latest)
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git ${COMFY_DIR} \
    && git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git ${COMFY_DIR}/custom_nodes/ComfyUI-GGUF \
    && git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git ${COMFY_DIR}/custom_nodes/ComfyUI-Manager \
    && pip install -r ${COMFY_DIR}/requirements.txt \
    && pip install -r ${COMFY_DIR}/custom_nodes/ComfyUI-GGUF/requirements.txt \
    && pip install -U "gguf>=0.13.0" huggingface_hub

# Fail the build early if this ComfyUI checkout is too old for Qwen-Image 2.1
RUN grep -q "TextEncodeQwenImage21" ${COMFY_DIR}/comfy_extras/nodes_qwen.py \
    || (echo "ERROR: ComfyUI checkout lacks TextEncodeQwenImage21 — rebuild with a newer ComfyUI" && exit 1)

COPY start.sh /start.sh
COPY workflows/ /opt/workflows/
COPY workflows/ ${COMFY_DIR}/user/default/workflows/
RUN chmod +x /start.sh \
    && mkdir -p /workspace

EXPOSE 8188
ENTRYPOINT ["/start.sh"]
