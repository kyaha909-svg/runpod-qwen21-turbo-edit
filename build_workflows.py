"""Generate the ComfyUI workflow JSONs (UI format + API format).

Edit graph (matches the Abiray model card + Comfy-Org Qwen-Image-2.1 template):
  UnetLoaderGGUF -> KSampler.model
  CLIPLoader(qwen_image) -> TextEncodeQwenImage21.clip
  VAELoader -> TextEncodeQwenImage21.vae + VAEDecode.vae
  LoadImage -> TextEncodeQwenImage21 [images.image_1]  (+ image_2 in the 2-ref file)
  TextEncodeQwenImage21 -> positive / negative / latent (latent = canvas from image_1)
  KSampler (steps 4, cfg 1.0, euler, simple, denoise 1.0) -> VAEDecode -> SaveImage
The dotted "images.image_N" key is the API spelling of the autogrow input group.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
WF_DIR = os.path.join(HERE, "workflows")
API_DIR = os.path.join(WF_DIR, "api")
os.makedirs(API_DIR, exist_ok=True)

DIT = "qwen_image_2.1_turbo_Q4_K_M.gguf"
ENC = "qwen3vl_8b_int8_convrot.safetensors"
VAE = "qwen_image_2.1_vae_bf16.safetensors"
EDIT_PROMPT = (
    "Change the background to a rainy cyberpunk street at night, "
    "keeping the person's face, pose and clothes unchanged."
)
NOTE = (
    "## Qwen-Image-2.1 Viggle Turbo — Image Edit\n"
    "1. LoadImage に編集したい画像を入れる（これが image_1 = 編集対象）\n"
    "2. TextEncodeQwenImage21 の prompt に編集指示を書く（参照画像は <image1> <image2> と呼ぶ）\n"
    "3. KSampler は固定: steps 4 / cfg 1.0 / euler / simple / denoise 1.0（上げると焼けます）\n"
    "4. resolution 1024 = 総画素数の目安。元画像の比率は維持される。0 で元サイズ\n"
    "出力は /workspace/output に保存されます。"
)


# ---------------------------------------------------------------- API format
def api_workflow(n_refs: int) -> dict:
    wf = {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": DIT},
              "_meta": {"title": "Unet Loader (GGUF) — Turbo Q4_K_M"}},
        "2": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": ENC, "type": "qwen_image", "device": "default"},
              "_meta": {"title": "Load CLIP — Qwen3-VL 8B int8"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": VAE},
              "_meta": {"title": "Load VAE"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": "example.png"},
              "_meta": {"title": "Load Image — edit target (image_1)"}},
    }
    enc_inputs = {
        "clip": ["2", 0], "vae": ["3", 0],
        "prompt": EDIT_PROMPT, "negative_prompt": "", "resolution": 1024,
        "images.image_1": ["4", 0],
    }
    if n_refs >= 2:
        wf["9"] = {"class_type": "LoadImage", "inputs": {"image": "example_ref.png"},
                   "_meta": {"title": "Load Image — reference (image_2)"}}
        enc_inputs["images.image_2"] = ["9", 0]
    wf["5"] = {"class_type": "TextEncodeQwenImage21", "inputs": enc_inputs,
               "_meta": {"title": "Text Encode Qwen Image 2.1 — edit instruction"}}
    wf["6"] = {"class_type": "KSampler",
               "inputs": {"model": ["1", 0], "positive": ["5", 0], "negative": ["5", 1],
                          "latent_image": ["5", 2], "seed": 42, "steps": 4, "cfg": 1.0,
                          "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0},
               "_meta": {"title": "KSampler — 4 steps / cfg 1.0 (fixed for Turbo)"}}
    wf["7"] = {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["3", 0]},
               "_meta": {"title": "VAE Decode"}}
    wf["8"] = {"class_type": "SaveImage",
               "inputs": {"images": ["7", 0], "filename_prefix": "qwen21_turbo_edit"},
               "_meta": {"title": "Save Image"}}
    return wf


def api_t2i() -> dict:
    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": DIT}},
        "2": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": ENC, "type": "qwen_image", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "4": {"class_type": "TextEncodeQwenImage21",
              "inputs": {"clip": ["2", 0], "vae": ["3", 0],
                         "prompt": "a red paper crane on a wooden desk, soft window light, photorealistic",
                         "negative_prompt": "", "resolution": 1024}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "6": {"class_type": "KSampler",
              "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["4", 1],
                         "latent_image": ["5", 0], "seed": 42, "steps": 4, "cfg": 1.0,
                         "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["3", 0]}},
        "8": {"class_type": "SaveImage",
              "inputs": {"images": ["7", 0], "filename_prefix": "qwen21_turbo_t2i"}},
    }


# ---------------------------------------------------------------- UI format
class Graph:
    def __init__(self):
        self.nodes = []
        self.links = []
        self._next_link = 1

    def link(self, origin, o_slot, target, t_slot, ltype):
        lid = self._next_link
        self._next_link += 1
        self.links.append([lid, origin, o_slot, target, t_slot, ltype])
        return lid

    def node(self, **kw):
        kw.setdefault("flags", {})
        kw.setdefault("mode", 0)
        kw.setdefault("properties", {"Node name for S&R": kw["type"]})
        self.nodes.append(kw)
        return kw


def ui_workflow(n_refs: int) -> dict:
    g = Graph()
    # Reserve link ids first by wiring after node creation: create nodes with
    # placeholder links, then patch. Simpler: create links in fixed order.
    L = {}
    L["model"] = g.link(1, 0, 6, 0, "MODEL")
    L["clip"] = g.link(2, 0, 5, 0, "CLIP")
    L["vae_enc"] = g.link(3, 0, 5, 1, "VAE")
    L["vae_dec"] = g.link(3, 0, 7, 1, "VAE")
    L["img1"] = g.link(4, 0, 5, 2, "IMAGE")
    if n_refs >= 2:
        L["img2"] = g.link(9, 0, 5, 3, "IMAGE")
    L["pos"] = g.link(5, 0, 6, 1, "CONDITIONING")
    L["neg"] = g.link(5, 1, 6, 2, "CONDITIONING")
    L["lat"] = g.link(5, 2, 6, 3, "LATENT")
    L["samp"] = g.link(6, 0, 7, 0, "LATENT")
    L["dec"] = g.link(7, 0, 8, 0, "IMAGE")

    enc_inputs = [
        {"name": "clip", "type": "CLIP", "link": L["clip"]},
        {"name": "vae", "type": "VAE", "link": L["vae_enc"]},
        {"name": "images.image_1", "shape": 7, "type": "IMAGE", "link": L["img1"]},
    ]
    if n_refs >= 2:
        enc_inputs.append({"name": "images.image_2", "shape": 7, "type": "IMAGE", "link": L["img2"]})

    g.node(id=1, type="UnetLoaderGGUF", pos=[40, 40], size=[330, 60], order=0,
           inputs=[], outputs=[{"name": "MODEL", "type": "MODEL", "links": [L["model"]]}],
           widgets_values=[DIT], title="Unet Loader (GGUF) — Turbo")
    g.node(id=2, type="CLIPLoader", pos=[40, 140], size=[330, 110], order=1,
           inputs=[], outputs=[{"name": "CLIP", "type": "CLIP", "links": [L["clip"]]}],
           widgets_values=[ENC, "qwen_image", "default"], title="Load CLIP — Qwen3-VL 8B int8")
    g.node(id=3, type="VAELoader", pos=[40, 290], size=[330, 60], order=2,
           inputs=[], outputs=[{"name": "VAE", "type": "VAE", "links": [L["vae_enc"], L["vae_dec"]]}],
           widgets_values=[VAE])
    g.node(id=4, type="LoadImage", pos=[40, 400], size=[330, 380], order=3,
           inputs=[], outputs=[{"name": "IMAGE", "type": "IMAGE", "links": [L["img1"]]},
                               {"name": "MASK", "type": "MASK", "links": None}],
           widgets_values=["example.png", "image"], title="Load Image — edit target (image_1)")
    if n_refs >= 2:
        g.node(id=9, type="LoadImage", pos=[40, 830], size=[330, 380], order=4,
               inputs=[], outputs=[{"name": "IMAGE", "type": "IMAGE", "links": [L["img2"]]},
                                   {"name": "MASK", "type": "MASK", "links": None}],
               widgets_values=["example_ref.png", "image"], title="Load Image — reference (image_2)")
    g.node(id=5, type="TextEncodeQwenImage21", pos=[430, 40], size=[440, 340],
           order=5, inputs=enc_inputs,
           outputs=[{"name": "positive", "type": "CONDITIONING", "links": [L["pos"]]},
                    {"name": "negative", "type": "CONDITIONING", "links": [L["neg"]]},
                    {"name": "latent", "type": "LATENT", "links": [L["lat"]]}],
           widgets_values=[EDIT_PROMPT, "", 1024],
           title="Text Encode Qwen Image 2.1 — edit instruction")
    g.node(id=6, type="KSampler", pos=[930, 40], size=[330, 300], order=6,
           inputs=[{"name": "model", "type": "MODEL", "link": L["model"]},
                   {"name": "positive", "type": "CONDITIONING", "link": L["pos"]},
                   {"name": "negative", "type": "CONDITIONING", "link": L["neg"]},
                   {"name": "latent_image", "type": "LATENT", "link": L["lat"]}],
           outputs=[{"name": "LATENT", "type": "LATENT", "links": [L["samp"]]}],
           widgets_values=[42, "randomize", 4, 1.0, "euler", "simple", 1.0],
           title="KSampler — 4 steps / cfg 1.0 (fixed)")
    g.node(id=7, type="VAEDecode", pos=[1330, 40], size=[210, 60], order=7,
           inputs=[{"name": "samples", "type": "LATENT", "link": L["samp"]},
                   {"name": "vae", "type": "VAE", "link": L["vae_dec"]}],
           outputs=[{"name": "IMAGE", "type": "IMAGE", "links": [L["dec"]]}],
           widgets_values=[])
    g.node(id=8, type="SaveImage", pos=[1330, 150], size=[330, 300], order=8,
           inputs=[{"name": "images", "type": "IMAGE", "link": L["dec"]}],
           outputs=[], widgets_values=["qwen21_turbo_edit"])
    g.node(id=10, type="MarkdownNote", pos=[430, 430], size=[440, 260], order=9,
           inputs=[], outputs=[], widgets_values=[NOTE], title="使い方")
    g.nodes.sort(key=lambda n: n["id"])
    return {
        "id": "qwen21-turbo-edit-1ref" if n_refs == 1 else "qwen21-turbo-edit-2ref",
        "revision": 0, "last_node_id": 10, "last_link_id": g._next_link - 1,
        "nodes": g.nodes, "links": g.links, "groups": [], "config": {},
        "extra": {"ds": {"scale": 0.8, "offset": [0, 0]}},
        "version": 0.4,
    }


def check_ui(wf: dict):
    node_ids = {n["id"] for n in wf["nodes"]}
    link_ids = set()
    for lid, o, _os, t, _ts, _ty in wf["links"]:
        assert o in node_ids and t in node_ids, f"link {lid} points at missing node"
        link_ids.add(lid)
    for n in wf["nodes"]:
        for inp in n.get("inputs", []):
            if inp.get("link") is not None:
                assert inp["link"] in link_ids, f"node {n['id']} input link not in links[]"
        for out in n.get("outputs", []):
            for l in out.get("links") or []:
                assert l in link_ids, f"node {n['id']} output link not in links[]"


def main():
    files = {
        os.path.join(API_DIR, "qwen21_turbo_edit_api.json"): api_workflow(1),
        os.path.join(API_DIR, "qwen21_turbo_edit_2ref_api.json"): api_workflow(2),
        os.path.join(API_DIR, "qwen21_turbo_t2i_api.json"): api_t2i(),
        os.path.join(WF_DIR, "qwen21_turbo_edit.json"): ui_workflow(1),
        os.path.join(WF_DIR, "qwen21_turbo_edit_2ref.json"): ui_workflow(2),
    }
    for path, data in files.items():
        if "workflows/api" not in path.replace(os.sep, "/"):
            check_ui(data)
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print("wrote", path)


if __name__ == "__main__":
    main()
