# Interactive SLURM SSH Sessions

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A streamlined solution for running interactive SSH sessions on SLURM compute nodes, designed for seamless integration with VSCode Remote-SSH and other development tools.

## 🚀 Quick Start

### Setup
**macOS / Linux**
```bash
git clone https://github.com/aihpi/interactive-slurm.git
cd interactive-slurm
./setup.sh
```

**Windows (PowerShell)**
```powershell
git clone https://github.com/aihpi/interactive-slurm.git
cd interactive-slurm
.\setup.ps1
```

Use `setup.sh` on macOS/Linux and `setup.ps1` on Windows.

The setup scripts automatically:
- ✅ Generates SSH keys and configures access
- ✅ Installs scripts on your HPC cluster
- ✅ Sets up VSCode integration
- ✅ Handles container options if needed

### Connect
```bash
ssh slurm-cpu
```

That's it! You now have access to a compute node with:
- VSCode Remote-SSH support
- Automatic updates (runs in background)
- Full SLURM integration
- Optional container support
- Multiple GPU types (A30 and H100)

## ✨ Features

- 🚀 **One-Command Setup**: Fully automated installation
- 🆙 **Auto-Updates**: Scripts update themselves automatically from GitHub
- 🎯 **VSCode Ready**: Perfect Remote-SSH integration
- 🔧 **Simple Management**: Use `remote` commands for all operations
- 🔐 **Secure**: Automatic SSH key management
- 🖥️ **Multiple GPU Types**: Support for A30 (gpuswap) and H100 GPUs
- ⚡ **H100 Performance**: Access to high-performance H100 GPUs on aisc-shortrun partition

## 📋 Prerequisites

- Access to a SLURM-managed HPC cluster
- SSH access to the cluster's login node
- VSCode with [Remote-SSH extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) (optional)

## 🖥️ Basic Usage

### Connect to CPU Environment
```bash
ssh slurm-cpu
```

### VSCode Integration
1. **Install Extension**: Get "Remote-SSH" from VSCode marketplace
2. **Connect**: Press `Ctrl/Cmd+Shift+P` → "Remote-SSH: Connect to Host"
3. **Select Host**: Choose `slurm-cpu` from the list
4. **Start Coding**: VSCode connects to the compute node automatically!

### Manage Sessions
```bash
# List running jobs
remote list

# Switch to A30 GPU environment
remote gpuswap

# Reserve H100 GPUs (default: 1 GPU)
remote h100

# Reserve multiple H100 GPUs (1-8)
remote h100 4

# Use H100 with container image
remote h100 2 /path/to/container.sqsh

# Exit all interactive sessions
remote exit

# Check for updates
remote check

# Update to latest version
remote update
```

## 🆙 Auto-Updates

**Automatic**: When you connect, scripts check for updates in the background (once daily) and apply them automatically.

**Manual Control**:
```bash
# Check for updates
remote check

# Force update
remote update
```

## 🛠️ Troubleshooting

### Common Issues

**Connection takes too long (>5 minutes):**
```bash
# Check job status
ssh login.hpc.yourcluster.edu
squeue --me
```

**VSCode connection fails:**
1. Test command line first: `ssh slurm-cpu`
2. Check VSCode timeout settings: `remote.SSH.connectTimeout ≥ 300`
3. View logs: VSCode → Output → Remote-SSH

**Get help:**
```bash
remote help
```

## 📚 More Information

- **Testing Guide**: [TESTING.md](TESTING.md)  
- **Technical Details**: [DEV.md](DEV.md)
- **Change Log**: [CHANGELOG.md](CHANGELOG.md)

## Based on

Interactive SLURM builds upon [vscode-remote-hpc](https://github.com/gmertes/vscode-remote-hpc) with enhanced automation and auto-update capabilities.
