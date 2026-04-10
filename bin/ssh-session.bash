#!/bin/bash

# Use the provided container image path (optional).
CONTAINER_IMAGE=$2
USE_CONTAINER=true

# If no container image is specified, run without container
if [ -z "$CONTAINER_IMAGE" ]; then
    echo "ℹ️ No container specified, running directly on compute node"
    USE_CONTAINER=false
fi

# Handle container validation and setup only if using container
if [ "$USE_CONTAINER" = true ]; then
    # Handle /sc/projects paths by copying to home directory if needed
    if [[ "$CONTAINER_IMAGE" =~ ^/sc/projects ]]; then
        # Extract filename from the path
        SQSH_FILENAME=$(basename "$CONTAINER_IMAGE")
        LOCAL_SQSH_PATH="$HOME/$SQSH_FILENAME"
        
        # If local copy doesn't exist, try to copy from /sc/projects
        if [ ! -f "$LOCAL_SQSH_PATH" ]; then
            echo "Copying $CONTAINER_IMAGE to $LOCAL_SQSH_PATH..."
            if cp "$CONTAINER_IMAGE" "$LOCAL_SQSH_PATH" 2>/dev/null; then
                echo "✅ Successfully copied sqsh file to home directory"
                CONTAINER_IMAGE="$LOCAL_SQSH_PATH"
            else
                echo "⚠️ Could not copy from /sc/projects, will try to use original path in container"
            fi
        else
            echo "ℹ️ Using existing sqsh file: $LOCAL_SQSH_PATH"
            CONTAINER_IMAGE="$LOCAL_SQSH_PATH"
        fi
    else
        # Check if the container image exists for non-/sc/projects paths
        if [ ! -f "$CONTAINER_IMAGE" ]; then
            echo "Error: Container image not found at '$CONTAINER_IMAGE'" >&2
            exit 1
        fi
    fi
fi

# Define the marker string to check if already added
MARKER="# >>> Slurm-over-SSH (auto-added) <<<"

# Check if SSH-over-SSH wrapper functions exist in bashrc
if grep -Fxq "$MARKER" "$HOME/.bashrc"; then
    # Remove SSH-over-SSH wrapper functions when NOT using containers
    if [ "$USE_CONTAINER" = false ]; then
        # Remove the SSH-over-SSH block from bashrc
        sed -i '/# >>> Slurm-over-SSH (auto-added) <<</,/# <<< Slurm-over-SSH (auto-added) >>>/d' "$HOME/.bashrc"
        echo "🗑️  Removed SSH-over-SSH wrappers (using direct Slurm commands)"
    else
        echo "ℹ️ SSH-over-SSH wrappers already present (container mode)"
    fi
else
    # Only add SSH-over-SSH wrapper functions when using containers
    if [ "$USE_CONTAINER" = true ]; then
        cat >> "$HOME/.bashrc" <<'EOF'

# >>> Slurm-over-SSH (auto-added) <<<
if ! command -v sinfo >/dev/null 2>&1; then
  export SLURM_LOGIN=10.130.0.6

  sinfo()  { ssh -q "$SLURM_LOGIN" sinfo  "$@"; }
  squeue() { ssh -q "$SLURM_LOGIN" squeue "$@"; }
  sbatch() { ssh -q "$SLURM_LOGIN" sbatch "$@"; }
  srun() { ssh -q "$SLURM_LOGIN" srun "$@"; }
  salloc() { ssh -q "$SLURM_LOGIN" salloc "$@"; }
  scancel(){ ssh -q "$SLURM_LOGIN" scancel "$@"; }
fi
# <<< Slurm-over-SSH (auto-added) >>>
EOF

        echo "✅ Added SSH-over-SSH wrappers (container mode)"
    else
        echo "ℹ️ Using direct Slurm commands (no wrappers needed)"
    fi
fi

# Add remote alias configuration
REMOTE_MARKER="# >>> Remote Alias Configuration (auto-added) <<<"
if ! grep -Fxq "$REMOTE_MARKER" "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<'EOF'

# >>> Remote Alias Configuration (auto-added) <<<
# Define the path to start-ssh-job.bash
SSH_JOB_SCRIPT="${HOME}/bin/start-ssh-job.bash"

# Add remote alias if the script exists
if [ -f "$SSH_JOB_SCRIPT" ]; then
    alias remote="$SSH_JOB_SCRIPT"
fi

# Function to display remote options when entering slurm-cpu environment
display_slurm_options() {
    echo "🖥️  Welcome to the CPU environment!"
    echo "📋 Available 'remote' commands:"
    echo "   • remote list       - List running vscode-remote jobs"
    echo "   • remote ssh        - SSH into the node of a running job"
    echo "   • remote gpuswap    - Switch to GPU environment"
    echo "   • remote h100 <1-8> - Reserve 1-8 H100 GPUs on aisc-shortrun partition"
    echo "   • remote exit       - Exit all jobs on aisc-interactive and aisc-shortrun partitions"
    echo "   • remote help       - Display full usage information"
    echo ""
    echo "💡 For GPU development:"
    echo "   • remote gpuswap    - Switch to GPU environment with salloc"
    echo "   • remote h100 <1-8> - Reserve 1-8 H100 GPUs on aisc-shortrun partition"
    echo ""
    echo "💡 To return to local environment:"
    echo "   • remote exit       - Exit all interactive sessions completely"
    echo ""
}

# Add completion for remote commands (optional)
if command -v complete &>/dev/null; then
    _remote_completion() {
        local cur prev opts
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        
        opts="list ssh gpuswap h100 exit help"
        
        if [[ ${cur} == -* ]] ; then
            COMPREPLY=( $(compgen -W "-h --help" -- ${cur}) )
            return 0
        fi
        
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    }
    
    complete -F _remote_completion remote
fi
# <<< Remote Alias Configuration (auto-added) >>>
EOF

  echo "✅ Remote alias configuration added to ~/.bashrc"
else
  echo "ℹ️ Remote alias configuration already present"
fi

# Add or refresh a lightweight login hint for interactive shells
REMOTE_HINT_MARKER="# >>> Remote Login Hint (auto-added) <<<"
if grep -Fxq "$REMOTE_HINT_MARKER" "$HOME/.bashrc"; then
  sed -i "/# >>> Remote Login Hint (auto-added) <<</,/# <<< Remote Login Hint (auto-added) >>>/d" "$HOME/.bashrc" 2>/dev/null || true
fi

cat >> "$HOME/.bashrc" <<'EOF'

# >>> Remote Login Hint (auto-added) <<<
REMOTE_HINT_SCRIPT="${HOME}/bin/start-ssh-job.bash"
if [[ $- == *i* ]] && [[ -t 0 ]] && [[ -t 1 ]] && [[ -f "$REMOTE_HINT_SCRIPT" ]] && [[ -z "${INTERACTIVE_SLURM_HINT_SHOWN:-}" ]]; then
    export INTERACTIVE_SLURM_HINT_SHOWN=1
    QUOTA_BAR_FILE="${HOME}/.sci/quota-bar"
    if [[ -f "$QUOTA_BAR_FILE" ]]; then
        quota_bar=$(sed -n 's/^bar=//p' "$QUOTA_BAR_FILE" | head -n1)
        quota_usage=$(sed -n 's/^usage=//p' "$QUOTA_BAR_FILE" | head -n1)
        quota_limit=$(sed -n 's/^quota=//p' "$QUOTA_BAR_FILE" | head -n1)
        quota_usage=${quota_usage//\\ / }
        quota_limit=${quota_limit//\\ / }
        if [[ -n "$quota_bar" || -n "$quota_usage" || -n "$quota_limit" ]]; then
            printf "💾  Quota: %b  %s / %s\n" "$quota_bar" "$quota_usage" "$quota_limit"
        fi
    fi
    echo "ℹ️  Interactive SLURM commands are available via 'remote'."
    echo "   Try 'remote help', 'remote list', 'remote gpuswap', 'remote h100 2', or 'remote exit'."
    echo ""
fi
# <<< Remote Login Hint (auto-added) >>>
EOF

echo "✅ Remote login hint configured in ~/.bashrc"

# Display remote options when entering the environment
if [ "$USE_CONTAINER" = true ]; then
    echo "🐳 Container: $(basename "$CONTAINER_IMAGE")"
fi
display_slurm_options

if [ "$USE_CONTAINER" = true ]; then
    echo "🐳 Starting SSH daemon in container: $(basename "$CONTAINER_IMAGE")"
    enroot start \
      --rw \
      --mount /usr/bin/srun:/usr/bin/srun \
      --mount /usr/bin/sbatch:/usr/bin/sbatch \
      --mount /usr/bin/scancel:/usr/bin/scancel \
      --mount /usr/lib/x86_64-linux-gnu/libslurm.so.41:/usr/lib/x86_64-linux-gnu/libslurm.so.41 \
      --mount /usr/lib/x86_64-linux-gnu/libslurm.so.41.0.0:/usr/lib/x86_64-linux-gnu/libslurm.so.41.0.0 \
      --mount /usr/lib/x86_64-linux-gnu/slurm-wlm:/usr/lib/x86_64-linux-gnu/slurm-wlm \
      --mount /usr/lib/x86_64-linux-gnu/libmunge.so.2:/usr/lib/x86_64-linux-gnu/libmunge.so.2 \
      "$CONTAINER_IMAGE" bash -c '
    if [ ! -d "${HOME:-~}/.ssh" ]; then
        mkdir -p ${HOME:-~}/.ssh
    fi

    if [ ! -f "${HOME:-~}/.ssh/vscode-remote-hostkey" ]; then
        ssh-keygen -t ed25519 -f ${HOME:-~}/.ssh/vscode-remote-hostkey -N ""
    fi

    if [ -f "/usr/sbin/sshd" ]; then
        sshd_cmd=/usr/sbin/sshd
    else
        sshd_cmd=sshd
    fi
    $sshd_cmd -D -p '$1' -f /dev/null -h ${HOME:-~}/.ssh/vscode-remote-hostkey
    '
else
    echo "🖥️  Starting SSH daemon directly on compute node"
    
    # Ensure SSH directory exists
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p "$HOME/.ssh"
    fi

    # Generate SSH host key if it doesn't exist
    if [ ! -f "$HOME/.ssh/vscode-remote-hostkey" ]; then
        ssh-keygen -t ed25519 -f "$HOME/.ssh/vscode-remote-hostkey" -N ""
    fi

    # Find sshd binary
    if [ -f "/usr/sbin/sshd" ]; then
        sshd_cmd=/usr/sbin/sshd
    else
        sshd_cmd=sshd
    fi

    # Start SSH daemon directly on the compute node
    exec $sshd_cmd -D -p $1 -f /dev/null -h "$HOME/.ssh/vscode-remote-hostkey"
fi
