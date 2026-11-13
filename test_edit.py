"""Headless image edit against a running pod (no browser needed).

Usage:
  python test_edit.py --url https://POD_ID-8188.proxy.runpod.net --image input.jpg --prompt "..."
  optional: --ref reference.png --seed 42

Uploads the image(s), posts workflows/api/qwen21_turbo_edit(_2ref)_api.json
to ComfyUI /prompt, waits, and downloads the result next to this script.
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))


def post_json(url, payload):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req).read())


def upload(base, path):
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        blob = f.read()
    name = os.path.basename(path)
    head = (
        "--" + boundary + "\r\n"
        + 'Content-Disposition: form-data; name="image"; filename="' + name + '"\r\n'
        + "Content-Type: application/octet-stream\r\n\r\n"
    ).encode()
    body = head + blob + ("\r\n--" + boundary + "--\r\n").encode()
    req = urllib.request.Request(
        base + "/upload/image", data=body,
        headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    return json.loads(urllib.request.urlopen(req).read())["name"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True, help="ComfyUI base URL of the pod")
    ap.add_argument("--image", required=True)
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--ref", default=None)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    base = args.url.rstrip("/")

    wf_name = "qwen21_turbo_edit_2ref_api.json" if args.ref else "qwen21_turbo_edit_api.json"
    with open(os.path.join(HERE, "workflows", "api", wf_name)) as f:
        wf = json.load(f)

    wf["4"]["inputs"]["image"] = upload(base, args.image)
    if args.ref:
        wf["9"]["inputs"]["image"] = upload(base, args.ref)
    wf["5"]["inputs"]["prompt"] = args.prompt
    wf["6"]["inputs"]["seed"] = args.seed

    prompt_id = post_json(base + "/prompt", {"prompt": wf})["prompt_id"]
    print("queued:", prompt_id)
    while True:
        time.sleep(3)
        with urllib.request.urlopen(base + "/history/" + prompt_id) as r:
            hist = json.loads(r.read())
        if prompt_id in hist:
            outputs = hist[prompt_id]["outputs"]["8"]["images"]
            break
    for img in outputs:
        q = urllib.parse.urlencode(
            {"filename": img["filename"], "subfolder": img.get("subfolder", ""),
             "type": img.get("type", "output")})
        out = os.path.join(HERE, "result_" + img["filename"])
        with urllib.request.urlopen(base + "/view?" + q) as r, open(out, "wb") as f:
            f.write(r.read())
        print("saved:", out)


if __name__ == "__main__":
    main()
