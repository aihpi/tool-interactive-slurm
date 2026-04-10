#!/bin/bash

# Set your Slurm parameters for CPU jobs here
SBATCH_PARAM_CPU="-o /dev/null -e /dev/null -t 8:00:00 -p aisc-interactive --account aisc --exclude=ga03 --mem=32GB --cpus-per-task=4 --export=ALL"

# The time you expect a job to start in (seconds)
# If a job doesn't start within this time, the script will exit and cancel the pending job
TIMEOUT=300

# Auto-update configuration (lightweight, runs in background)
UPDATE_VERSION_FILE="$HOME/.interactive-slurm.version"
UPDATE_LOG="$HOME/.interactive-slurm.update.log"
UPDATE_DIR="$HOME/.interactive-slurm-updates"
REPO_URL="https://github.com/aihpi/interactive-slurm.git"
UPDATE_INTERVAL=86400  # 24 hours in seconds

####################
# don't edit below this line
####################

function usage ()
{
    echo "Usage: remote [command]

    General commands:
    list      List running vscode-remote jobs
    ssh       SSH into the node of a running job
    help      Display this message
    check     Check for Interactive SLURM updates
    update    Update Interactive SLURM to latest version

    Job commands:
    cpu [path]       Connect to a CPU node, optionally specifying a container image path
    gpuswap          Swap to A30 GPU environment with salloc reservation
    h100 [1-8] [path] Reserve 1-8 H100 GPUs on aisc-shortrun partition (default: 1)
    "
}

# Auto-update functions (run silently in background)
function silent_update_check() {
    # Skip if auto-update is disabled
    if [ -f "$HOME/.interactive-slurm.noauto" ]; then
        return 1
    fi
    
    # Check if enough time has passed since last update
    if [ -f "$UPDATE_VERSION_FILE" ]; then
        LAST_UPDATE=$(stat -c %Y "$UPDATE_VERSION_FILE" 2>/dev/null)
        if [ -z "$LAST_UPDATE" ]; then
            return 1
        fi
        
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_UPDATE))

        # Only check for updates every 24 hours
        if [ $TIME_DIFF -lt $UPDATE_INTERVAL ]; then
            return 1
        fi
    fi

    
    # Perform silent update in background
    (
        perform_auto_update >/dev/null 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Silent auto-update completed" >> "$UPDATE_LOG" 2>/dev/null
    ) &
}

function get_current_version() {
    if [ -f "$UPDATE_VERSION_FILE" ]; then
        cat "$UPDATE_VERSION_FILE"
    else
        echo "unknown"
    fi
}

function perform_auto_update() {
    if ! command -v git &> /dev/null; then
        return 1
    fi
    
    # Initialize/update git repo if needed
    if [ ! -d "$UPDATE_DIR/.git" ]; then
        mkdir -p "$UPDATE_DIR"
        git clone --depth 1 "$REPO_URL" "$UPDATE_DIR" 2>/dev/null || return 1
    fi
    
    cd "$UPDATE_DIR"
    
    # Check for updates
    git fetch origin main 2>/dev/null || return 1
    
    LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
    REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null || echo "")
    
    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ] && [ -n "$REMOTE_HASH" ]; then
        # Update available, apply it
        git pull origin main 2>/dev/null || return 1
        
        # Backup current installation
        if [ -d "$HOME/bin" ]; then
            cp -r "$HOME/bin" "${HOME/bin}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
        
        # Update scripts
        mkdir -p "$HOME/bin"
        cp bin/* "$HOME/bin/" 2>/dev/null || true
        chmod +x "$HOME/bin"/*.bash "$HOME/bin"/*.sh 2>/dev/null || true
        
        # Update version
        echo "$REMOTE_HASH" > "$UPDATE_VERSION_FILE"
        
        return 0
    fi
    
    return 1
}

function check_for_updates() {
    echo "🔍 Checking for Interactive SLURM updates..."
    
    if ! command -v git &> /dev/null; then
        echo "❌ Git not available on this system"
        return 1
    fi
    
    # Perform quick update check
    (
        if [ ! -d "$UPDATE_DIR/.git" ]; then
            echo "📥 Initializing update repository..."
            git clone --depth 1 "$REPO_URL" "$UPDATE_DIR" 2>/dev/null
        fi
        
        if [ -d "$UPDATE_DIR/.git" ]; then
            cd "$UPDATE_DIR"
            if git fetch origin main 2>/dev/null; then
                LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null || echo "unknown")
                
                if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
                    echo "✅ Updates available!"
                    echo "   Current: ${LOCAL_HASH:0:7}"
                    echo "   Latest:  ${REMOTE_HASH:0:7}"
                    echo ""
                    echo "Run '~/bin/start-ssh-job.bash update' to install updates"
                else
                    echo "✅ Already running latest version"
                fi
            fi
        fi
    )
}

function update_interactive_slurm() {
    echo "🚀 Updating Interactive SLURM..."
    
    if ! command -v git &> /dev/null; then
        echo "❌ Git not available on this system"
        return 1
    fi
    
    if perform_auto_update; then
        CURRENT_VERSION=$(get_current_version)
        echo "✅ Update completed successfully!"
        echo "   Version: ${CURRENT_VERSION:0:7}"
        echo ""
        echo "🎉 Interactive SLURM is now up to date!"
    else
        echo "ℹ️  No updates available or update failed"
        echo "   Current version: $(get_current_version)"
    fi
}

function query_slurm () {
    # only list states that can result in a running job
    list=($(squeue --me --states=R,PD,S,CF,RF,RH,RQ -h -O JobId:" ",Name:" ",State:" ",NodeList:" " | grep $JOB_NAME))

    if [ ! ${#list[@]} -eq 0 ]; then
        JOB_ID=${list[0]}
        JOB_FULLNAME=${list[1]}
        JOB_STATE=${list[2]}
        JOB_NODE=${list[3]}

        split=(${JOB_FULLNAME//%/ })
        JOB_PORT=${split[1]}

        >&2 echo "Job is $JOB_STATE ( id: $JOB_ID, name: $JOB_FULLNAME${JOB_NODE:+, node: $JOB_NODE} )" 
    else
        JOB_ID=""
        JOB_FULLNAME=""
        JOB_STATE=""
        JOB_NODE=""
        JOB_PORT=""
    fi
}

function cleanup () {
    if [ ! -z "${JOB_SUBMIT_ID}" ]; then
        scancel $JOB_SUBMIT_ID
        >&2 echo "Cancelled pending job $JOB_SUBMIT_ID"
    fi
    if [ ! -z "${SRUN_PID}" ]; then
        if kill -0 $SRUN_PID 2>/dev/null; then
            kill $SRUN_PID 2>/dev/null
            >&2 echo "Killed srun process $SRUN_PID"
        fi
    fi
}

function timeout () {
    if (( $(date +%s)-START > TIMEOUT )); then 
        >&2 echo "Timeout, exiting..."
        cleanup
        exit 1
    fi
}

function exit_session () {
    echo "👋 Exiting all interactive sessions..."
    echo "🔄 Cancelling all jobs on aisc-interactive and aisc-shortrun partitions"
    echo ""

    # Cancel all jobs on aisc-shortrun partition  
    SHORTRUN_JOB_COUNT=$(squeue --me --states=R,PD,S,CF,RF,RH,RQ -p aisc-shortrun -h | wc -l)
    if [ $SHORTRUN_JOB_COUNT -gt 0 ]; then
        echo "🔄 Cancelling $SHORTRUN_JOB_COUNT job(s) on aisc-shortrun partition..."
        scancel --partition=aisc-shortrun --user=$USER
    fi

    # Cancel all jobs on aisc-interactive partition
    INTERACTIVE_JOB_COUNT=$(squeue --me --states=R,PD,S,CF,RF,RH,RQ -p aisc-interactive -h | wc -l)
    if [ $INTERACTIVE_JOB_COUNT -gt 0 ]; then
        echo "🔄 Cancelling $INTERACTIVE_JOB_COUNT job(s) on aisc-interactive partition..."
        scancel --partition=aisc-interactive --user=$USER
    fi

    TOTAL_JOBS=$((INTERACTIVE_JOB_COUNT + SHORTRUN_JOB_COUNT))
    
    echo ""
    if [ $TOTAL_JOBS -gt 0 ]; then
        echo "✅ Successfully cancelled $TOTAL_JOBS job(s)"
    else
        echo "ℹ️ No jobs found to cancel on interactive partitions"
    fi
    
    echo ""
    echo "Goodbye! 🎉"
    exit 0
}

function list_jobs () {
    width=$((${#JOB_NAME} + 11))
    echo "$(which squeue)"
    echo "$(squeue --me -O JobId,Partition,Name:$width,State,TimeUsed,TimeLimit,NodeList | grep -E "JOBID|$JOB_NAME")"
}

function ssh_connect () {
    JOB_NAME=$JOB_NAME-cpu
    query_slurm
    CPU_NODE=$JOB_NODE

    if [ -z "${CPU_NODE}" ]; then
        echo "No running CPU job found"
        exit 1
    fi

    echo "Connecting to $CPU_NODE (CPU) via SSH"
    ssh $CPU_NODE
}

function detect_current_job_constraints() {
    # Get constraints from the current CPU job using scontrol
    query_slurm
    
    if [ -z "${JOB_ID}" ]; then
        >&2 echo "No current job found"
        return 1
    fi
    
    >&2 echo "📋 Analyzing current job $JOB_ID..."
    
    # Get detailed job information using scontrol
    JOB_INFO=$(scontrol show job $JOB_ID 2>/dev/null)
    
    if [ -n "$JOB_INFO" ]; then
        >&2 echo "✅ Found job details"
        
        # Extract ExcNodeList (excluded nodes) from scontrol output
        EXCLUDE_NODES=$(echo "$JOB_INFO" | grep -o "ExcNodeList=[^[:space:]]*" | cut -d= -f2)
        
        if [ -n "$EXCLUDE_NODES" ]; then
            >&2 echo "   Excluded nodes: $EXCLUDE_NODES"
            echo "--exclude=$EXCLUDE_NODES"
        else
            >&2 echo "   No excluded nodes found"
            echo ""
        fi
    else
        >&2 echo "⚠️ Unable to get job details"
        return 1
    fi
}

function gpuswap () {
    # GPU Swap Command - Reserve GPU on demand and display greeting
    CONTAINER_IMAGE_PATH=$1

    echo "🚀 Starting GPU session reservation..."
    echo "📋 Allocating GPU resources on aisc-interactive partition"
    echo "⏱️  Time limit: 01:00:00"
    echo "🎯 Account: aisc"
    echo "💾 GPU: 1x GPU"

    # Detect current job constraints to ensure GPU job matches CPU job architecture
    CURRENT_CONSTRAINTS=$(detect_current_job_constraints)
    
    if [ $? -eq 0 ] && [ -n "$CURRENT_CONSTRAINTS" ]; then
        echo "🏗️  Using same architecture constraints as current job"
        echo "🔧 Constraints: $CURRENT_CONSTRAINTS"
    else
        echo "ℹ️  No current job found or unable to detect constraints"
        echo "🔧 Using default GPU allocation"
    fi

    if [ -n "$CONTAINER_IMAGE_PATH" ]; then
        echo "🐳 Container: $CONTAINER_IMAGE_PATH"
        echo ""
        echo "🔄 Executing: salloc -p aisc-interactive --account aisc --gres=gpu:1 --time=01:00:00 $CURRENT_CONSTRAINTS"
        echo "🎉 Welcome to your GPU session! GPU resources are being reserved."
        echo "📝 You can now run GPU-accelerated commands in this environment."
        echo ""
        echo "💡 To exit the GPU session, simply type 'exit' or press Ctrl+D"
        echo "🔄 To return to CPU environment, use the 'remote' command"
        echo ""
        
        # Run salloc with container support and current job constraints
        echo "🔄 Executing: salloc -p aisc-interactive --account aisc --gres=gpu:1 --time=01:00:00 $CURRENT_CONSTRAINTS"
        echo "🎉 Welcome to your GPU session! GPU resources are being reserved."
        echo "📝 You can now run GPU-accelerated commands in this environment."
        echo ""
        echo "💡 To exit the GPU session, simply type 'exit' or press Ctrl+D"
        echo "🔄 To return to CPU environment, use the 'remote' command"
        echo ""
        echo "💭 Note: To end GPU session, use 'exit'"
        echo ""
        
        # Run salloc with container support and current job constraints
        salloc --job-name="$JOB_NAME-gpuswap-container" -p aisc-interactive --account aisc --gres=gpu:1 --time=01:00:00 $CURRENT_CONSTRAINTS --container-image="$CONTAINER_IMAGE_PATH" "$@"
    else
        echo ""
        echo "🔄 Executing: salloc -p aisc-interactive --account aisc --gres=gpu:1 --time=01:00:00 $CURRENT_CONSTRAINTS"
        echo "🎉 Welcome to your GPU session! GPU resources are being reserved."
        echo "📝 You can now run GPU-accelerated commands in this environment."
        echo ""
        echo "💡 To exit the GPU session, simply type 'exit' or press Ctrl+D"
        echo "🔄 To return to CPU environment, use the 'remote' command"
        echo ""
        echo "💭 Note: To end GPU session, use 'exit'"
        echo ""
        
        # Run salloc without container but with current job constraints
        salloc --job-name="$JOB_NAME-gpuswap" -p aisc-interactive --account aisc --gres=gpu:1 --mem=80GB --cpus-per-task=8 --time=01:00:00 $CURRENT_CONSTRAINTS
    fi

    echo ""
    echo "🔍 GPU Information:"
    if nvidia-smi >/dev/null 2>&1; then
        echo "✅ GPU successfully detected and accessible!"
        echo "🎯 GPU Resources Available:"
        nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits
    else
        echo "⚠️ nvidia-smi not available in this environment"
    fi

    echo "👋 GPU session ended. Returning to CPU environment..."
}

function h100 () {
    # H100 GPU Command - Reserve H100 on aisc-shortrun partition
    # Support: h100 [1-8] [container_path]
    
    # Parse arguments
    GPU_COUNT=1
    CONTAINER_IMAGE_PATH=""
    
    if [ $# -eq 0 ]; then
        # No arguments: reserve 1 H100 GPU
        GPU_COUNT=1
    elif [ $# -eq 1 ]; then
        # One argument: could be container path or gpu count
        if [ -f "$1" ]; then
            # It's a file path (container)
            CONTAINER_IMAGE_PATH="$1"
            GPU_COUNT=1
        else
            # It's a number (GPU count)
            GPU_COUNT="$1"
        fi
    elif [ $# -ge 2 ]; then
        # Two or more arguments: first is GPU count, rest is container
        GPU_COUNT="$1"
        CONTAINER_IMAGE_PATH="$2"
        # Shift remaining arguments for container options
        shift
        shift
        OTHER_ARGS="$@"
    fi

    if ! [[ "$GPU_COUNT" =~ ^[1-8]$ ]]; then
        echo "Error: H100 GPU count must be an integer from 1 to 8." >&2
        echo "Usage: remote h100 [1-8] [container_path]" >&2
        return 1
    fi

    echo "🚀 Starting H100 session reservation..."
    echo "📋 Allocating H100 GPU resources on aisc-shortrun partition"
    echo "⏱️  Time limit: 01:00:00"
    echo "🎯 Account: aisc"
    echo "💾 GPU: ${GPU_COUNT}x H100"

    if [ -n "$CONTAINER_IMAGE_PATH" ]; then
        echo "🐳 Container: $CONTAINER_IMAGE_PATH"
        echo ""
        echo "🔄 Executing: salloc -p aisc-shortrun --account aisc --gres=gpu:h100:${GPU_COUNT} --time=01:00:00"
        echo "🎉 Welcome to your H100 session! H100 GPU resources are being reserved."
        echo "📝 You can now run H100-accelerated commands in this environment."
        echo ""
        echo "💡 To exit the H100 session, simply type 'exit' or press Ctrl+D"
        echo "🔄 To return to CPU environment, use the 'remote' command"
        echo ""
        echo "💭 Note: To end H100 session, use 'exit'"
        echo ""
        
        # Run salloc with container support
        salloc --job-name="$JOB_NAME-h100-container" -p aisc-shortrun --account aisc --gres=gpu:h100:${GPU_COUNT} --mem=80GB --cpus-per-task=8 --time=01:00:00 --container-image="$CONTAINER_IMAGE_PATH" $OTHER_ARGS
    else
        echo ""
        echo "🔄 Executing: salloc -p aisc-shortrun --account aisc --gres=gpu:h100:${GPU_COUNT} --time=01:00:00"
        echo "🎉 Welcome to your H100 session! H100 GPU resources are being reserved."
        echo "📝 You can now run H100-accelerated commands in this environment."
        echo ""
        echo "💡 To exit the H100 session, simply type 'exit' or press Ctrl+D"
        echo "🔄 To return to CPU environment, use the 'remote' command"
        echo ""
        echo "💭 Note: To end H100 session, use 'exit'"
        echo ""
        
        # Run salloc without container
        salloc --job-name="$JOB_NAME-h100" -p aisc-shortrun --account aisc --gres=gpu:h100:${GPU_COUNT} --time=01:00:00
    fi

    echo ""
    echo "🔍 H100 GPU Information:"
    if nvidia-smi >/dev/null 2>&1; then
        echo "✅ H100 GPU successfully detected and accessible!"
        echo "🎯 H100 GPU Resources Available:"
        nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits
    else
        echo "⚠️ nvidia-smi not available in this environment"
    fi

    echo "👋 H100 session ended. Returning to CPU environment..."
}

function connect () {
    CONTAINER_IMAGE_PATH=$1
    
    # Perform silent auto-update check (runs in background, doesn't block)
    silent_update_check
    
    query_slurm

    if [ -z "${JOB_STATE}" ]; then
        PORT=$(shuf -i 10000-65000 -n 1)

        # Use srun for interactive partition (runs in background)
        if [ -n "$CONTAINER_IMAGE_PATH" ]; then
            nohup srun -J $JOB_NAME%$PORT $SBATCH_PARAM $SCRIPT_DIR/ssh-session.bash $PORT "$CONTAINER_IMAGE_PATH" > /dev/null 2>&1 &
            SRUN_PID=$!
            >&2 echo "Started new $JOB_NAME job with container (srun pid: $SRUN_PID port: $PORT)"
        else
            nohup srun -J $JOB_NAME%$PORT $SBATCH_PARAM $SCRIPT_DIR/ssh-session.bash $PORT > /dev/null 2>&1 &
            SRUN_PID=$!
            >&2 echo "Started new $JOB_NAME job without container (srun pid: $SRUN_PID port: $PORT)"
        fi

        # Give srun a moment to submit the job
        sleep 2
    fi

    while [ ! "$JOB_STATE" == "RUNNING" ]; do
        timeout
        sleep 5
        query_slurm
    done

    >&2 echo "Connecting to $JOB_NODE"

    while ! nc -z $JOB_NODE $JOB_PORT; do
        timeout
        sleep 1
    done

    # Display welcome message for CPU environment
    echo "🖥️  Welcome to the CPU environment!"
    echo "📋 Available commands:"
    echo "   • 'remote gpuswap' - Switch to GPU environment"
    echo "   • 'remote h100 N'  - Reserve 1-8 H100 GPUs on aisc-shortrun partition"
    echo "   • 'remote exit'  - Cancel all interactive sessions"
    echo ""
    if [ -n "$CONTAINER_IMAGE_PATH" ]; then
        echo "🐳 Container: $(basename "$CONTAINER_IMAGE_PATH")"
    fi

    nc $JOB_NODE $JOB_PORT
}

if [ ! -z "$1" ]; then
    JOB_NAME=remote
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    START=$(date +%s)
    trap "cleanup && exit 1" INT TERM
    COMMAND=$1
    shift
    case $COMMAND in
        list)   list_jobs ;;
        cancel) cancel ;;
        ssh)    ssh_connect ;;
        cpu)    JOB_NAME=$JOB_NAME-cpu; SBATCH_PARAM=$SBATCH_PARAM_CPU; connect "$@" ;;
        gpuswap) gpuswap "$@" ;;
        h100)   h100 "$@" ;;
        exit)   exit_session ;;
        check)  check_for_updates ;;
        update) update_interactive_slurm ;;
        help)   usage ;;
        *)  echo -e "Command '$COMMAND' does not exist" >&2
            usage; exit 1 ;;
    esac
    exit 0
else
    usage
    exit 0
fi
