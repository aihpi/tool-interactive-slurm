# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-04-10

### Added - Setup & Access Options
- **Run Node SSH Hosts**: Setup scripts can now generate direct `run-rx01` and `run-rx02` SSH hosts for lightweight always-on access without a Slurm job
- **Windows Setup Path**: README now explicitly documents `setup.ps1` for Windows users and `setup.sh` for macOS/Linux users
- **Manual Cleanup Command**: Added `remote cleanup` to manually prune older VSCode server installs on demand

### Changed - SSH Setup Defaults
- **CPU-Only Generated SSH Config**: Setup scripts no longer generate `slurm-gpu` or `slurm-gpu-container` SSH hosts
- **Container Prompt Warning**: Container opt-in prompts are now marked as experimental in both setup scripts
- **Remote Help Text**: Usage output now presents commands as `remote [command]` instead of showing the script path
- **H100 Command Guidance**: Help text, startup hints, and README examples now document `remote h100 <1-8>`

### Fixed - Shell Setup & Session UX
- **PATH Export Duplication**: Setup scripts now check `~/.bashrc` directly before appending `export PATH="$HOME/bin:$PATH"`, and bash setup cleans older duplicate entries
- **PowerShell PATH Quoting**: Windows setup now writes the correct remote PATH export line without malformed escaping
- **Temporary Install Script Cleanup**: Bash setup now removes `~/install_interactive_slurm.sh` from the cluster after installation
- **CPU Job Log Cleanup**: CPU interactive jobs now send stdout/stderr to `/dev/null` instead of creating `job.logs`
- **Daily VSCode Server Cleanup**: The once-per-day background maintenance runner now prunes older `~/.vscode-server` installs and keeps the newest two versions
- **Interactive Terminal Hint**: Compute-node shells now show a compact `remote` usage hint only in real interactive TTY sessions
- **Quota Summary Display**: Startup hint can now display the cluster-provided quota summary from `~/.sci/quota-bar`
- **H100 Input Validation**: `remote h100` now validates GPU counts and rejects values outside `1` to `8`

## [Unreleased] - 2025-11-26

### Enhanced - GPU Session Management & H100 Support
- **H100 GPU Reservation**: New `remote h100` command for reserving H100 GPUs on aisc-shortrun partition
- **Configurable GPU Count**: H100 command supports specifying GPU count (default: 1) and container images
- **Enhanced Session Exit**: Replaced `remote cancel` with `remote exit` for comprehensive session cleanup
- **Partition-Specific Cleanup**: Exit command now cancels jobs on both aisc-interactive and aisc-shortrun partitions
- **Improved Job Naming**: Enhanced job naming conventions for better tracking (remote-gpuswap, remote-h100, etc.)
- **Better User Feedback**: Enhanced messaging for session management and job cancellation
- **Updated Command Completion**: Bash completion updated to reflect new command structure
- **GPU Environment Clarification**: gpuswap now explicitly mentions A30 GPU environment

### Changed - Command Line Interface
- **Removed**: `remote cancel` command (replaced by `remote exit`)
- **Added**: `remote h100` for H100 GPU reservations
- **Added**: `remote exit` for comprehensive session cleanup
- **Updated**: Help text and documentation to reflect new command structure

### Technical Improvements
- **Session Management**: More robust handling of multiple partition jobs
- **Job Cleanup**: Enhanced scancel commands with proper partition targeting
- **Error Handling**: Better feedback when no jobs are found to cancel
- **Container Support**: H100 command supports both containerized and non-containerized execution

## [Unreleased] - 2025-09-12

### Fixed - Setup Script Improvements & noexec Filesystem Compatibility
- **noexec Filesystem Support**: ProxyCommand now uses `bash ~/bin/start-ssh-job.bash` to bypass noexec restrictions on NFS home directories
- **Duplicate SSH Entry Prevention**: Setup script now cleans existing Interactive SLURM entries before adding new ones, preventing conflicts
- **Enhanced Script Permissions**: Added explicit chmod commands and verification for critical scripts during installation
- **SSH Config Management**: Automatic cleanup of old SSH configurations ensures the latest settings are always used

### Added - Major Release: Optional Containers & Automated Setup
- **Automated Setup Script**: New `setup.sh` provides one-command installation with interactive prompts
- **Optional Container Support**: Can now run with or without enroot containers
- **SSH Key Management**: Automatic generation and distribution of SSH keys (`~/.ssh/interactive-slurm`)
- **VSCode Integration**: Automatic configuration of Remote-SSH extension settings
- **Container Auto-copy**: Setup script can copy containers from `/sc/projects` to home directory
- **Connection Validation**: Built-in testing and troubleshooting during setup
- **Comprehensive Documentation**: New TESTING.md with step-by-step testing guide
- **Enhanced README**: Complete tutorial with clear local vs remote machine indicators

### Added - Auto-Update System & Documentation Restructuring
- **Auto-Update System**: Scripts now automatically update themselves from GitHub when connecting via SSH
- **Remote Update Commands**: New `remote check` and `remote update` commands for manual update management
- **Background Updates**: Update checks run silently in background (once daily) during SSH connections
- **Safe Update Mechanism**: Current installation backed up before applying updates, with restore capability
- **Developer Documentation**: Created comprehensive DEV.md with technical implementation details
- **Documentation Split**: Streamlined README.md for users, technical details moved to DEV.md
- **Update Control**: Users can disable auto-updates with `~/.interactive-slurm.noauto`
- **Update Logging**: All update operations logged to `~/.interactive-slurm.update.log`
- **Version Tracking**: Current version tracked in `~/.interactive-slurm.version`

### Enhanced
- **Dual Execution Modes**: Both containerized (enroot) and direct compute node access
- **Smart Container Detection**: Scripts automatically detect container presence/absence
- **Improved Error Messages**: Better feedback for containerless vs container modes
- **SSH Configuration**: Auto-generated SSH configs with appropriate timeouts and settings
- **User Experience**: Emoji-enhanced output and clear step-by-step guidance

### Changed
- **Container Parameter**: Now optional in `start-ssh-job.bash cpu [path]` and `gpu [path]`
- **SSH Session Logic**: Conditional execution based on container availability
- **Documentation Structure**: README focused on automated setup, manual config moved to advanced section
- **Project Architecture**: Added setup.sh as primary entry point

### Technical Improvements
- **Session Management**: Enhanced `ssh-session.bash` with dual-mode execution
- **Error Handling**: Better validation and fallback mechanisms
- **Tool Detection**: Improved validation of required tools with warnings vs errors

## [Previous] - 2025-09-11

### Added
- **Automatic sqsh file management**: `ssh-session.bash` now automatically copies container images from `/sc/projects` to the user's home directory if they don't exist locally
- **Comprehensive Slurm integration**: Added mounting of Slurm binaries (`srun`, `sbatch`, `scancel`) and libraries (`libslurm.so.*`, `libmunge.so.2`) for full cluster access within containers
- **SSH daemon setup**: Containers now automatically generate SSH host keys and set up proper SSH daemon configuration
- **Slurm command aliases**: Added automatic SSH-over-Slurm command wrappers to `~/.bashrc` for seamless cluster command execution
- **Container initialization script**: Added `incontainer-setup.sh` for standardized container environment setup

### Changed
- **CPU job parameters**: Updated `SBATCH_PARAM_CPU` to use x86 architecture constraint, reduced memory to 16GB and CPU cores to 4 for better resource efficiency
- **GPU job parameters**: Added `--export=IN_ENROOT=1` environment variable export
- **Container image validation**: Improved path validation to handle mounted directories like `/sc/projects` more intelligently
- **Error handling**: Enhanced error messages and fallback mechanisms for container image access

### Enhanced
- **Job scheduling**: Jobs now target x86 architecture specifically to avoid library compatibility issues on ARM nodes
- **Resource management**: Optimized CPU job resource allocation for typical development workloads
- **Container portability**: Improved support for shared container images stored in project directories

### Technical Details
- Container images from `/sc/projects` are automatically cached locally to avoid mounting issues
- Slurm library versions 40 and 41 are both supported through dynamic mounting
- SSH daemon runs on dynamically allocated ports to prevent conflicts
- All Slurm commands work transparently within containers via SSH forwarding
