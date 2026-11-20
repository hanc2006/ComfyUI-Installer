# Headless ComfyUI Installer

Install and run ComfyUI on a Linux server or GPU pod without a desktop environment, interactive prompts, or systemd.

Requires an NVIDIA GPU with compatible drivers, Git, Python 3, and Python's `venv` and `pip` modules.

## RunPod setup

Use a GPU pod with persistent storage mounted at `/workspace`. Clone the repository there so the installer, virtual environment, and ComfyUI files persist when the pod restarts:

```sh
cd /workspace
git clone https://github.com/hanc2006/ComfyUI-Installer.git
cd ComfyUI-Installer
```

Edit the static settings at the top of `scripts/config.sh` if needed. The default configuration uses port `8188` and keeps all files in the cloned repository directory.

Install ComfyUI:

```sh
./install.sh
```

Install the included custom nodes:

```sh
./scripts/install_custom_nodes.sh
```

Edit the repository URL list in the script to change which nodes are installed.
Existing node directories are kept without updating them; their `requirements.txt`,
if present, is installed into the ComfyUI virtual environment on every run.
Some nodes may require additional setup or dependencies; consult their documentation.
Restart ComfyUI after installing nodes.

Download the models listed in `scripts/download_models.sh`:

```sh
./scripts/download_models.sh
```

Edit the `MODELS` list in the script to change the Hugging Face repository,
remote file path, or destination under `ComfyUI/models`. Set `HF_TOKEN` in
`scripts/config.sh` for gated repositories; the Hugging Face CLI is installed
into the ComfyUI virtual environment automatically if needed. Existing non-empty
model files are skipped.

Install File Browser to manage `/workspace`:

```sh
./scripts/install_filebrowser.sh
```

The script prints the generated `admin` credentials and saves them in plaintext
at `/workspace/filebrowser-credentials.txt` (owner-only permissions). Protect
that file and console output. The credentials file is not updated if the
password is changed later. The installer refuses to overwrite existing File
Browser files. Start File Browser with:

```sh
/workspace/.filebrowser/filebrowser -d /workspace/.filebrowser/filebrowser.db
```

It listens on `127.0.0.1:8080`; use an SSH tunnel to access it remotely.
The original File Browser project is archived and has unresolved security
issues. Do not expose it directly to the internet; use a reverse proxy with
TLS and separate authentication if remote exposure is required. Run it as an
unprivileged user and keep command execution disabled.

Start ComfyUI:

```sh
./scripts/run_comfyui.sh
```

Expose port `8188` in the pod settings to access the web interface. Keep the process running in the terminal, or configure the pod's startup command to run `./scripts/run_comfyui.sh`.

ComfyUI listens on all network interfaces. Protect access to the exposed port; do not make it publicly accessible without authentication.

The installer builds SageAttention 2.2.0 in the
ComfyUI environment and the launcher enables it with `--use-sage-attention`.
This requires a supported NVIDIA GPU (compute capability 8.0, 8.6, 8.9, 9.0,
or 12.0), a C++ build toolchain, and the CUDA toolkit with `nvcc` (not just the
driver). CUDA 12.0 or newer is required for Ampere, 12.4 for Ada, 12.3 for
Hopper, and 12.8 for Blackwell. The toolkit should match PyTorch's CUDA
version. See the [SageAttention installation instructions](https://github.com/thu-ml/SageAttention/tree/v2.2.0#installation).
Set `SAGE_ATTENTION=false` before installing or launching to use ComfyUI's
default attention instead. Changing the setting to `true` requires rerunning
`./install.sh`.

Running `./install.sh` again restores dependencies for an existing ComfyUI installation and rebuilds SageAttention when enabled. To update ComfyUI itself, run:

```sh
source venv/bin/activate
comfy --workspace="$PWD/ComfyUI" --skip-prompt update comfy
```

Adjust those paths if you changed them in `scripts/config.sh`.
