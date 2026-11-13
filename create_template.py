"""Create the RunPod Pod template from runpod-template.json.

Usage:
  export RUNPOD_API_KEY=...        # RunPod -> Settings -> API Keys
  python create_template.py        # prints the template id + deploy URL

The API key is read from the environment only — never hard-code it here.
"""
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> int:
    api_key = os.environ.get("RUNPOD_API_KEY")
    if not api_key:
        print("ERROR: set RUNPOD_API_KEY in the environment first.", file=sys.stderr)
        return 1
    with open(os.path.join(HERE, "runpod-template.json")) as f:
        body = json.load(f)
    body.pop("_comment", None)
    if "YOUR_DOCKERHUB_USER" in body["imageName"]:
        print("ERROR: replace imageName in runpod-template.json with your pushed image first.",
              file=sys.stderr)
        return 1
    req = urllib.request.Request(
        "https://rest.runpod.io/v1/templates",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {api_key}",
                 "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"RunPod API error {e.code}: {e.read().decode(errors='replace')}", file=sys.stderr)
        return 1
    tid = data.get("id") or data.get("templateId") or "(see response below)"
    print(json.dumps(data, indent=2, ensure_ascii=False))
    print()
    print(f"Template ID: {tid}")
    print(f"Deploy URL : https://console.runpod.io/deploy?template={tid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
