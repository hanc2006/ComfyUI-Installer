# Headless ComfyUI Installer

Install and run ComfyUI on a Linux server or GPU pod without a desktop environment, interactive prompts, or systemd.

Requires Git, Python 3, and Python's `venv` and `pip` modules. GPU use also requires compatible drivers.

## RunPod setup

Use a GPU pod with persistent storage mounted at `/workspace`. Clone the repository there so the installer, virtual environment, and ComfyUI files persist when the pod restarts:

```sh
cd /workspace
git clone https://github.com/hanc2006/ComfyUI-Installer.git
cd ComfyUI-Installer
```

Edit the static settings at the top of `scripts/config.sh` if needed. The default configuration uses NVIDIA, port `8188`, and keeps all files in the cloned repository directory.

Install ComfyUI:

```sh
./install.sh
```

Start ComfyUI:

```sh
./scripts/run_comfyui.sh
```

Expose port `8188` in the pod settings to access the web interface. Keep the process running in the terminal, or configure the pod's startup command to run `./scripts/run_comfyui.sh`.

ComfyUI listens on all network interfaces. Protect access to the exposed port; do not make it publicly accessible without authentication.

Set `GPU_TYPE` in `scripts/config.sh` to `amd`, `cpu`, or `auto` to change the installation target. The `cpu` setting also starts ComfyUI in CPU mode.

Running `./install.sh` again restores dependencies for an existing ComfyUI installation. To update ComfyUI itself, run:

```sh
source venv/bin/activate
comfy --workspace="$PWD/ComfyUI" --skip-prompt update comfy
```

Adjust those paths if you changed them in `scripts/config.sh`.
