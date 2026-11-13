# Qwen-Image-2.1 Viggle Turbo (GGUF) 画像編集 — RunPod ワンクリックテンプレート

`Abiray/Qwen-Image-2.1-viggle-4-steps-turbo-GGUF` を使って、ComfyUI で
**指示文による画像編集**（元画像＋編集指示 → 編集結果）ができる RunPod Pod テンプレートです。

- モデルはイメージに焼き込まず、**初回起動時に永続ボリューム `/workspace` へ自動ダウンロード**（約14.2GB）。2回目以降は即起動します
- 編集用ワークフロー（参照1枚／2枚）を同梱し、ComfyUI の Workflow メニューからそのまま開けます
- 生成設定は蒸留モデルの固定値にプリセット済み：**steps 4 / cfg 1.0 / euler / simple / denoise 1.0 / ネガティブ空**
  （25〜40ステップに上げると画質が崩れます。変更しないでください）

## 含まれるモデル（初回起動時に自動DL）

| 役割 | ファイル | サイズ | 取得元 |
|---|---|---|---|
| 本体 (DiT, GGUF) | `qwen_image_2.1_turbo_Q4_K_M.gguf` | 4.19GB | Abiray/Qwen-Image-2.1-viggle-4-steps-turbo-GGUF |
| テキストエンコーダー | `qwen3vl_8b_int8_convrot.safetensors` | 9.35GB | Comfy-Org/Qwen-Image-2.1 |
| VAE | `qwen_image_2.1_vae_bf16.safetensors` | 0.68GB | Comfy-Org/Qwen-Image-2.1 |

3点とも公開リポジトリで、HF_TOKEN は不要です。

## ファイル構成

```
Dockerfile            ベース: runpod/pytorch (CUDA 12.8) + ComfyUI最新版 + ComfyUI-GGUF
start.sh              初回DL → /workspace へ配置 → ComfyUI起動 (8188)
workflows/
  qwen21_turbo_edit.json         編集ワークフロー（UI形式・参照1枚）
  qwen21_turbo_edit_2ref.json    編集ワークフロー（UI形式・参照2枚）
  api/qwen21_turbo_edit_api.json       API形式（1枚）
  api/qwen21_turbo_edit_2ref_api.json  API形式（2枚）
  api/qwen21_turbo_t2i_api.json        API形式（テキスト生成・おまけ）
runpod-template.json  テンプレート定義（API作成用）
create_template.py    RUNPOD_API_KEY でテンプレートをAPI作成するスクリプト
test_edit.py          ブラウザなしで編集を1回実行する確認用クライアント
build_workflows.py    ワークフローJSONの生成元（直す場合はこちらを編集して再実行）
```

## 手順1：Dockerイメージを build & push

Docker が動くマシンで（Docker Hub のユーザー名に読み替えてください）：

```bash
cd runpod-qwen21-turbo-edit
docker build -t YOUR_DOCKERHUB_USER/qwen21-turbo-edit:latest .
docker push YOUR_DOCKERHUB_USER/qwen21-turbo-edit:latest
```

- GHCR でも構いません（`ghcr.io/<user>/qwen21-turbo-edit:latest`）。その場合は手順2の Image も同じ値にします
- ビルド時に「ComfyUI に `TextEncodeQwenImage21` があるか」を自動チェックし、古い場合はビルドが失敗します（正常な安全装置です）

## 手順2：RunPod テンプレートを作成（1回だけ）

### 方法A：コンソール（推奨）

RunPod コンソール → **Templates → New Template** に、次の値をそのまま入力します。

| 項目 | 値 |
|---|---|
| Name | `Qwen-Image-2.1 Turbo GGUF — Image Edit (ComfyUI)` |
| Template Type | Pod |
| Container Image | `YOUR_DOCKERHUB_USER/qwen21-turbo-edit:latest`（手順1で push したもの） |
| Container Start Command | （空欄。イメージ側の ENTRYPOINT が起動します） |
| Container Disk | `40` GB |
| Volume Disk | `50` GB |
| Volume Mount Path | `/workspace` |
| HTTP Ports | `8188` |
| TCP Ports | `22` |
| Env: `GGUF_QUANT` | `Q4_K_M` |
| Env: `LOWVRAM` | `auto` |
| Env: `COMFY_PORT` | `8188` |

保存すると Template ID が発行されます。以後のデプロイはこのURLがワンクリックになります：

```
https://console.runpod.io/deploy?template=<Template ID>
```

### 方法B：API（任意）

```bash
# runpod-template.json の imageName を push 済みイメージに書き換えてから
export RUNPOD_API_KEY=<RunPod Settings → API Keys で発行>
python create_template.py   # Template ID と Deploy URL を表示します
```

APIキーは環境変数でのみ渡します。ファイルやチャットに書かないでください。

## 手順3：Pod をデプロイ

Deploy URL（または Templates → Deploy）を開き、GPU を選んで **Deploy On-Demand**。

- **推奨：VRAM 24GB 級**（RTX 4090 / L4 / L40S / A100 など）。エンコーダー9.35GB＋本体4.19GB＋編集時の活性化で、24GB あると 1024px 編集が安定します
- **最小：VRAM 16GB**。Q4_K_M＋`LOWVRAM=auto`（16GB以下は自動で `--lowvram`）で動作想定です。解像度は 1024 から始めてください
- CUDA 12.8 系イメージです。RTX 5090 等の Blackwell ではドライバー／CUDA の組み合わせに注意してください（起動しない場合は 24GB 級の Ada / Ampere 機を選ぶのが確実です）
- 料金は GPU 選択画面の表示が正です。初回はモデルDL（約14.2GB）の数分も課金時間に含まれます

## 手順4：画像編集の使い方

1. Pod が Running になったら **Connect → HTTP Service [Port 8188]** を開く（初回はDL完了まで 502/接続待ちが出ます。Pod の Logs に `[start] Launching ComfyUI` が出れば完了）
2. ComfyUI 左メニュー **Workflow** から `qwen21_turbo_edit` を開く
3. **Load Image** ノードに編集したい画像をドラッグ＆ドロップ（これが `image_1`＝編集対象）
4. **TextEncodeQwenImage21** の prompt に編集指示を書く
   例：`Change the background to a rainy cyberpunk street at night, keeping the person's face and pose unchanged`
   参照2枚版では、指示の中で `<image1>` `<image2>` と呼び分けます
5. **Queue** を押す。4ステップなので数十秒級で終わります
6. 結果は画面表示のほか `/workspace/output`（Pod のファイルブラウザ／Jupyter から取得可）に保存されます。**Pod を Terminate するとボリュームも消える**プランでは、先にダウンロードしてください（Network Volume を付ければ残ります）

ブラウザなしの確認用：

```bash
python test_edit.py --url https://<POD_ID>-8188.proxy.runpod.net \
  --image input.jpg --prompt "Change the background to a beach at sunset"
```

## 設定（環境変数）

| 変数 | 既定 | 説明 |
|---|---|---|
| `GGUF_QUANT` | `Q4_K_M` | 本体の量子化。`Q5_K_M`(5.01GB) / `Q6_K`(5.88GB) / `Q8_0`(7.59GB・VRAM16GB+) に上げると高画質寄り、`Q4_K_S` / `Q3_K_M` は低VRAM用。切替時は初回DLが走ります |
| `LOWVRAM` | `auto` | `auto`=VRAM 16GB以下で `--lowvram` 自動付加。`on` / `off` で固定も可 |
| `COMFY_PORT` | `8188` | ComfyUI のポート。通常は変更不要 |
| `HF_TOKEN` | （空） | 不要（3点とも公開）。設定しても害はありません |

## トラブルシューティング

- **`ValueError: This model is not currently supported (Unknown model architecture!)`**
  ComfyUI / ComfyUI-GGUF が古いです。イメージを再 build してください（最新版を取得し直します）
- **起動直後に 8188 が開かない**
  初回は約14.2GBのDL中です。Logs で `[start] downloading:` の進行を確認してください。再起動すると続きから再開します（`wget -c`）
- **編集で OOM**
  `resolution` を 1024 → 768 に下げる／参照画像を1枚にする／`GGUF_QUANT=Q4_K_S` に下げる、の順に試してください
- **結果が焼けた・崩れる**
  steps や cfg を上げた場合に起きます。steps 4 / cfg 1.0 に戻してください（蒸留モデルの仕様です）

## 注意

- ライセンスは **Qwen Research License（非商用・研究／評価目的）** です。商用利用は別途ライセンスが必要です
- このテンプレートはあなたの RunPod アカウント内に作るプライベートテンプレートです。公開（Public）にすると他ユーザーも使えますが、イメージ側も公開リポジトリである必要があります
- Kaggle 版と違い、トンネルは不要です（RunPod のプロキシURLでそのまま開けます）。URL は Pod ID を含むため、共有は控えてください
