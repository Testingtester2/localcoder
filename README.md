# Local Coder Kit

A local coding assistant for Windows PCs with an NVIDIA GPU. No cloud, no API bill.

- **Model:** Qwen3.8 27B (or Qwen3.6 35B-A3B), GGUF quants by Unsloth
- **Server:** llama.cpp, official CUDA build, listening on `127.0.0.1` only with a random key
- **Agent:** OpenCode, running inside a Docker container that only sees the one project folder you give it

Every download is checked against the publisher's SHA-256 (GitHub release digests, Hugging Face LFS hashes) before it is kept. A file that does not match is deleted.

## Requirements

- Windows 10 or 11
- NVIDIA GPU with 24 GB VRAM or more (tested on an RTX 5090, 32 GB), current driver
- Docker Desktop with the WSL2 backend, running
- 25 to 65 GB of free disk, depending on which models you take

## Install

1. Clone or download this repo to a fast drive (an NVMe SSD makes model loading much quicker).
2. Start Docker Desktop.
3. Double-click `Install.bat`, or run it from PowerShell for options:

```powershell
.\install.ps1                                      # picks a model for your GPU
.\install.ps1 -Models qwen3.8-27b-q6,qwen3.6-35b-a3b
.\install.ps1 -Models all
.\install.ps1 -SkipModels                          # tools only
```

Running it again is safe. Anything already downloaded and verified is skipped.

## Use

1. `Start-LLM.bat` starts the model server. Leave the window open. Closing it stops the server and frees the VRAM.
2. `Start-Agent.bat "C:\code\my-project"` opens OpenCode on that folder.

Pick a model or change the context size:

```
Start-LLM.bat qwen3.6-35b-a3b
Start-LLM.bat qwen3.8-27b-q6 -Ctx 32768
```

The server uses most of the GPU. Do not run it at the same time as other heavy GPU work such as ComfyUI renders or games.

## Models

| id | File | Size | Good for |
|---|---|---|---|
| `qwen3.8-27b-q6` | Qwen3.8-27B-UD-Q6_K | 22.0 GB | Best quality on 32 GB cards, 64K context |
| `qwen3.8-27b-q4` | Qwen3.8-27B-UD-Q4_K_M | 16.6 GB | 24 GB cards (32K context), or 128K context on 32 GB |
| `qwen3.6-35b-a3b` | Qwen3.6-35B-A3B-UD-Q4_K_M | 22.1 GB | Faster replies (MoE, 3B active), weaker on long agent runs |
| `qwen3.8-27b-mtp` | mtp-Qwen3.8-27B-Q4_0 | 1.4 GB | Optional speed head, see below |

If the server runs out of memory, lower `-Ctx`. All files come from `huggingface.co/unsloth`. Model ids and context sizes live in `config\models.json`.

**Speed head (experimental).** `Start-LLM.bat qwen3.8-27b-q6 -Mtp` loads the MTP head for speculative decoding. It has not been tested with this kit yet. If the server will not start with it, run without `-Mtp`.

## What the sandbox does

- The container sees only the project folder (mounted at `/work`). It cannot see the rest of your drives or run Windows programs.
- It runs as a normal user with all Linux capabilities dropped, no privilege escalation, and memory and process limits.
- Every file edit and every shell command asks you first.
- These are blocked outright: `git push`, `git remote`, `curl`, `wget`, `rm -rf`, `sudo`, `ssh`, `scp`, web fetch, and paths outside the project.
- OpenCode session sharing and auto-update are off.
- The model server only listens on `127.0.0.1` and needs the key in `llm.key`, which is generated on install and never committed.

What it does not do:

- The container still has internet access. OpenCode downloads its OpenAI-compatible provider package from npm the first time it runs.
- Anything the agent writes inside your project folder is real. Use git, so you can review and undo its changes.
- Permission prompts only help if you read them before you approve.

To change the rules, edit `config\opencode.json` and run `install.ps1` again to rebuild the image.

## Updating

Versions are pinned in `config\versions.json` (llama.cpp build tag and OpenCode release). Change them and run `install.ps1` again.

## Uninstall

```powershell
.\uninstall.ps1           # removes llama.cpp, key, Docker image and volumes, keeps models
.\uninstall.ps1 -Models   # also deletes the models
```

Nothing outside this folder and Docker is changed by the kit, so after that you can delete the folder.

## Credits and licenses

- **Kit:** only scripts and config. The tools and models it downloads keep their own licenses.
- **Models:** Qwen models by Alibaba (Apache 2.0); GGUF quants by Unsloth.
- **llama.cpp:** by ggml-org, https://github.com/ggml-org/llama.cpp
- **OpenCode:** https://github.com/anomalyco/opencode
