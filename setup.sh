#!/bin/bash

# Interactive SLURM SSH Sessions Setup Script
# This script guides you through the complete setup process

set -e

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if running on local machine or HPC
detect_environment() {
    if command -v squeue &> /dev/null; then
        echo "hpc"
    else
        echo "local"
    fi
}

# Validate required tools
validate_tools() {
    print_header "Validating Required Tools"
    
    local missing_tools=()
    local warnings=()
    
    # Check for ssh
    if ! command -v ssh &> /dev/null; then
        missing_tools+=("ssh")
    fi
    
    # Check for ssh-keygen
    if ! command -v ssh-keygen &> /dev/null; then
        missing_tools+=("ssh-keygen")
    fi
    
    # Check for nc (netcat) - warn but don't fail
    if ! command -v nc &> /dev/null && ! command -v netcat &> /dev/null; then
        warnings+=("netcat (nc) - required on HPC login node for SSH proxying")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install these tools before running the setup."
        exit 1
    fi
    
    if [ ${#warnings[@]} -ne 0 ]; then
        for warning in "${warnings[@]}"; do
            print_warning "Tool not found locally: $warning"
        done
        print_info "This is OK if you're running setup on your local machine"
        print_info "These tools are required on the HPC login node"
    fi
    
    print_success "Essential tools are available"
}

# Get user input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    echo -n "${prompt} [${default}]: "
    read -r input
    if [ -z "$input" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

# Get yes/no input
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    while true; do
        if [ "$default" = "y" ]; then
            echo -n "${prompt} [Y/n]: "
        else
            echo -n "${prompt} [y/N]: "
        fi
        
        read -r input
        case "$input" in
            [Yy]|[Yy][Ee][Ss]) eval "$var_name=true"; break ;;
            [Nn]|[Nn][Oo]) eval "$var_name=false"; break ;;
            "") 
                if [ "$default" = "y" ]; then
                    eval "$var_name=true"
                else
                    eval "$var_name=false"
                fi
                break ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Generate SSH key
setup_ssh_key() {
    print_header "SSH Key Setup"
    
    SSH_KEY_PATH="$HOME/.ssh/interactive-slurm"
    
    if [ -f "$SSH_KEY_PATH" ]; then
        print_warning "SSH key already exists at $SSH_KEY_PATH"
        prompt_yes_no "Do you want to overwrite it?" "n" "overwrite_key"
        
        if [ "$overwrite_key" = false ]; then
            print_info "Using existing SSH key"
            return 0
        fi
    fi
    
    print_info "Generating SSH key at $SSH_KEY_PATH"
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "interactive-slurm-$(date +%Y%m%d)"
    
    if [ $? -eq 0 ]; then
        print_success "SSH key generated successfully"
        echo -e "\n${BLUE}Public key content:${NC}"
        cat "${SSH_KEY_PATH}.pub"
        echo
    else
        print_error "Failed to generate SSH key"
        exit 1
    fi
}

# Get HPC configuration
get_hpc_config() {
    print_header "HPC Cluster Configuration"
    
    echo "Please provide your HPC cluster details:"
    echo
    
    prompt_with_default "HPC Login Node (hostname or IP)" "10.130.0.6" "HPC_LOGIN"
    prompt_with_default "Your username on the HPC cluster" "john.doe" "HPC_USERNAME"
    prompt_yes_no "Generate direct SSH hosts for Run Nodes?" "y" "ENABLE_RUN_NODES"
    
    if [ "$ENABLE_RUN_NODES" = true ]; then
        prompt_with_default "Run Node 1 hostname" "rx01.hpc.sci.hpi.de" "RUN_NODE_1"
        prompt_with_default "Run Node 2 hostname" "rx02.hpc.sci.hpi.de" "RUN_NODE_2"
    else
        RUN_NODE_1=""
        RUN_NODE_2=""
    fi
    
    print_info "Configuration set:"
    print_info "  Login Node: $HPC_LOGIN"
    print_info "  Username: $HPC_USERNAME"
    if [ "$ENABLE_RUN_NODES" = true ]; then
        print_info "  Run Nodes: $RUN_NODE_1, $RUN_NODE_2"
    fi
}

# Copy SSH key to HPC
copy_ssh_key_to_hpc() {
    print_header "Copying SSH Key to HPC Cluster"
    
    print_info "Copying public key to $HPC_USERNAME@$HPC_LOGIN"
    print_warning "You may be prompted for your HPC password"
    
    if ssh-copy-id -i "$SSH_KEY_PATH" "$HPC_USERNAME@$HPC_LOGIN"; then
        print_success "SSH key copied successfully"
    else
        print_error "Failed to copy SSH key"
        print_info "You can manually copy the key later with:"
        print_info "ssh-copy-id -i $SSH_KEY_PATH $HPC_USERNAME@$HPC_LOGIN"
        
        prompt_yes_no "Continue with setup anyway?" "y" "continue_setup"
        if [ "$continue_setup" = false ]; then
            exit 1
        fi
    fi
}

# Container configuration
setup_containers() {
    print_header "Container Configuration"
    
    prompt_yes_no "Do you want to use containers? (experimental)" "y" "USE_CONTAINERS"
    
    if [ "$USE_CONTAINERS" = true ]; then
        echo
        print_info "Container setup options:"
        
        prompt_yes_no "Do you have containers in /sc/projects that you want to copy?" "y" "COPY_FROM_SC_PROJECTS"
        
        if [ "$COPY_FROM_SC_PROJECTS" = true ]; then
            echo
            print_info "Available .sqsh files in /sc/projects:"
            echo "Please check what's available and specify the paths you want to copy."
            echo "Example paths:"
            echo "  /sc/projects/sci-aisc/sqsh-files/pytorch_ssh.sqsh"
            echo "  /sc/projects/shared/ubuntu22-cuda.sqsh"
            echo
            
            prompt_with_default "Container path to copy (full path)" "/sc/projects/sci-aisc/sqsh-files/pytorch_ssh.sqsh" "CONTAINER_SOURCE_PATH"
            CONTAINER_FILENAME=$(basename "$CONTAINER_SOURCE_PATH")
            CONTAINER_LOCAL_PATH="$HOME/$CONTAINER_FILENAME"
            
            print_info "Will copy: $CONTAINER_SOURCE_PATH"
            print_info "To: $CONTAINER_LOCAL_PATH"
        else
            prompt_with_default "Local container path (in your home directory)" "$HOME/my-container.sqsh" "CONTAINER_LOCAL_PATH"
        fi
        
        print_success "Container configuration complete"
    else
        print_info "No containers will be used - direct compute node access"
        CONTAINER_LOCAL_PATH=""
    fi
}

# Install scripts on HPC
install_hpc_scripts() {
    print_header "Installing Scripts on HPC Cluster"
    
    print_info "Connecting to HPC cluster to install scripts..."
    
    # Create the installation commands
    cat > /tmp/hpc_install_commands.sh << 'EOF'
#!/bin/bash

# Create bin directory
mkdir -p ~/bin

# Add bin to PATH in ~/.bashrc if not already there, and clean duplicates from prior installs
if [ -f ~/.bashrc ]; then
    awk '
        $0 == "export PATH=\"$HOME/bin:$PATH\"" {
            if (seen_path_line++) next
        }
        { print }
    ' ~/.bashrc > ~/.bashrc.interactive-slurm.tmp && mv ~/.bashrc.interactive-slurm.tmp ~/.bashrc
fi

if ! grep -Fqx 'export PATH="$HOME/bin:$PATH"' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/bin to PATH in ~/.bashrc"
fi

echo "HPC setup completed successfully"
EOF

    # Copy the installation script and bin files
    print_info "Copying installation script..."
    scp -i "$SSH_KEY_PATH" /tmp/hpc_install_commands.sh "$HPC_USERNAME@$HPC_LOGIN:~/install_interactive_slurm.sh"
    
    print_info "Copying interactive-slurm scripts..."
    scp -i "$SSH_KEY_PATH" bin/* "$HPC_USERNAME@$HPC_LOGIN:~/bin/"
    
    print_info "Running installation on HPC..."
    if ssh -i "$SSH_KEY_PATH" "$HPC_USERNAME@$HPC_LOGIN" "chmod +x ~/install_interactive_slurm.sh && bash ~/install_interactive_slurm.sh && chmod +x ~/bin/*.bash ~/bin/*.sh && chmod +x ~/bin/start-ssh-job.bash ~/bin/ssh-session.bash ~/bin/incontainer-setup.sh"; then
        ssh -i "$SSH_KEY_PATH" "$HPC_USERNAME@$HPC_LOGIN" "rm -f ~/install_interactive_slurm.sh" >/dev/null 2>&1 || true
    else
        ssh -i "$SSH_KEY_PATH" "$HPC_USERNAME@$HPC_LOGIN" "rm -f ~/install_interactive_slurm.sh" >/dev/null 2>&1 || true
        exit 1
    fi
    
    print_info "Verifying script permissions..."
    ssh -i "$SSH_KEY_PATH" "$HPC_USERNAME@$HPC_LOGIN" "ls -la ~/bin/*.bash ~/bin/*.sh | head -5"
    
    # Copy container if specified
    if [ "$USE_CONTAINERS" = true ] && [ "$COPY_FROM_SC_PROJECTS" = true ]; then
        print_info "Copying container file..."
        ssh -i "$SSH_KEY_PATH" "$HPC_USERNAME@$HPC_LOGIN" "cp '$CONTAINER_SOURCE_PATH' '$CONTAINER_LOCAL_PATH'" || {
            print_warning "Failed to copy container file. You may need to copy it manually later."
        }
    fi
    
    # Clean up
    rm /tmp/hpc_install_commands.sh
    
    print_success "Scripts installed on HPC cluster"
}

# Clean existing Interactive SLURM entries from SSH config
clean_existing_ssh_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        return 0
    fi
    
    # Create a temporary file without Interactive SLURM sections
    local temp_file=$(mktemp)
    local in_slurm_section=false
    
    while IFS= read -r line; do
        # Check if we're entering an Interactive SLURM section
        if echo "$line" | grep -q "=== Interactive SLURM SSH Sessions"; then
            in_slurm_section=true
            continue
        fi
        
        # Check if we're exiting an Interactive SLURM section
        if echo "$line" | grep -q "=== End Interactive SLURM SSH Sessions ==="; then
            in_slurm_section=false
            continue
        fi
        
        # Only write lines that are not in a SLURM section
        if [ "$in_slurm_section" = false ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$config_file"
    
    # Replace the original file with the cleaned version
    mv "$temp_file" "$config_file"
}

# Generate SSH config
generate_ssh_config() {
    print_header "Generating SSH Configuration"
    
    SSH_CONFIG_FILE="$HOME/.ssh/config"
    SSH_CONFIG_BACKUP="$HOME/.ssh/config.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Backup existing config
    if [ -f "$SSH_CONFIG_FILE" ]; then
        print_info "Backing up existing SSH config to $SSH_CONFIG_BACKUP"
        cp "$SSH_CONFIG_FILE" "$SSH_CONFIG_BACKUP"
    fi
    
    # Clean existing Interactive SLURM entries
    if [ -f "$SSH_CONFIG_FILE" ]; then
        print_info "Removing existing Interactive SLURM SSH entries..."
        clean_existing_ssh_config "$SSH_CONFIG_FILE"
    fi
    
    # Create SSH config entries
    print_info "Adding SSH configuration entries..."
    
    cat >> "$SSH_CONFIG_FILE" << EOF

# === Interactive SLURM SSH Sessions (generated $(date)) ===

# Direct compute node access (no container)
Host slurm-cpu
    HostName $HPC_LOGIN
    User $HPC_USERNAME
    IdentityFile $SSH_KEY_PATH
    ConnectTimeout 60
    ProxyCommand ssh $HPC_LOGIN -l $HPC_USERNAME -i $SSH_KEY_PATH "bash ~/bin/start-ssh-job.bash cpu"
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

EOF

    if [ "$ENABLE_RUN_NODES" = true ]; then
        cat >> "$SSH_CONFIG_FILE" << EOF
# Direct run node access (no Slurm job required)
Host run-rx01
    HostName $RUN_NODE_1
    User $HPC_USERNAME
    IdentityFile $SSH_KEY_PATH
    ConnectTimeout 60
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host run-rx02
    HostName $RUN_NODE_2
    User $HPC_USERNAME
    IdentityFile $SSH_KEY_PATH
    ConnectTimeout 60
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

EOF
    fi

    # Add container configs if containers are used
    if [ "$USE_CONTAINERS" = true ]; then
        cat >> "$SSH_CONFIG_FILE" << EOF
# Container-based access
Host slurm-cpu-container
    HostName $HPC_LOGIN
    User $HPC_USERNAME
    IdentityFile $SSH_KEY_PATH
    ConnectTimeout 60
    ProxyCommand ssh $HPC_LOGIN -l $HPC_USERNAME -i $SSH_KEY_PATH "bash ~/bin/start-ssh-job.bash cpu $CONTAINER_LOCAL_PATH"
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

EOF
    fi
    
    cat >> "$SSH_CONFIG_FILE" << EOF
# === End Interactive SLURM SSH Sessions ===

EOF
    
    print_success "SSH configuration generated"
    print_info "Available SSH hosts:"
    print_info "  • ssh slurm-cpu    (CPU job, direct access)"
    if [ "$ENABLE_RUN_NODES" = true ]; then
        print_info "  • ssh run-rx01     (Run node access, no Slurm job)"
        print_info "  • ssh run-rx02     (Run node access, no Slurm job)"
    fi
    
    if [ "$USE_CONTAINERS" = true ]; then
        print_info "  • ssh slurm-cpu-container (CPU job with container)"
    fi
}

# Configure VSCode
configure_vscode() {
    print_header "VSCode Configuration"
    
    VSCODE_SETTINGS_DIR=""
    
    # Detect VSCode settings location
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        # Windows
        VSCODE_SETTINGS_DIR="$APPDATA/Code/User"
    fi
    
    if [ -n "$VSCODE_SETTINGS_DIR" ] && [ -d "$VSCODE_SETTINGS_DIR" ]; then
        print_info "Found VSCode settings directory: $VSCODE_SETTINGS_DIR"
        
        VSCODE_SETTINGS_FILE="$VSCODE_SETTINGS_DIR/settings.json"
        
        prompt_yes_no "Configure VSCode settings for remote SSH?" "y" "CONFIGURE_VSCODE"
        
        if [ "$CONFIGURE_VSCODE" = true ]; then
            # Create backup
            if [ -f "$VSCODE_SETTINGS_FILE" ]; then
                cp "$VSCODE_SETTINGS_FILE" "${VSCODE_SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            fi
            
            # Create or update settings
            if [ ! -f "$VSCODE_SETTINGS_FILE" ]; then
                echo "{}" > "$VSCODE_SETTINGS_FILE"
            fi
            
            # Add/update remote SSH settings
            python3 -c "
import json
import os

settings_file = '$VSCODE_SETTINGS_FILE'
try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except:
    settings = {}

# Add remote SSH timeout
settings['remote.SSH.connectTimeout'] = 300

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print('VSCode settings updated successfully')
" 2>/dev/null || {
                print_warning "Could not automatically update VSCode settings"
                print_info "Please manually add this to your VSCode settings.json:"
                print_info '  "remote.SSH.connectTimeout": 300'
            }
            
            print_success "VSCode settings configured"
        fi
    else
        print_warning "VSCode settings directory not found"
    fi
    
    print_info "VSCode Remote-SSH Extension:"
    print_info "  1. Install the 'Remote - SSH' extension from the marketplace"
    print_info "  2. Use Ctrl/Cmd+Shift+P and search 'Remote-SSH: Connect to Host'"
    print_info "  3. Select one of your configured hosts (slurm-cpu, run-rx01, run-rx02, etc.)"
}

# Test connection
test_connection() {
    print_header "Testing Connection"
    
    prompt_yes_no "Test SSH connection to HPC cluster?" "y" "TEST_CONNECTION"
    
    if [ "$TEST_CONNECTION" = true ]; then
        print_info "Testing basic SSH connection..."
        
        if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o BatchMode=yes "$HPC_USERNAME@$HPC_LOGIN" "echo 'SSH connection successful'" 2>/dev/null; then
            print_success "SSH connection test passed"
            
            print_info "Testing SLURM availability..."
            if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$HPC_USERNAME@$HPC_LOGIN" "command -v squeue >/dev/null && echo 'SLURM available'" 2>/dev/null | grep -q "SLURM available"; then
                print_success "SLURM is available on the cluster"
            else
                print_warning "SLURM may not be available or not in PATH"
            fi
            
            print_info "Testing required tools on cluster..."
            ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$HPC_USERNAME@$HPC_LOGIN" "
                echo 'Testing tools on HPC cluster:'
                command -v nc >/dev/null && echo '✅ netcat (nc) available' || echo '❌ netcat (nc) missing'
                command -v sshd >/dev/null && echo '✅ sshd available' || echo '❌ sshd missing'
                command -v enroot >/dev/null && echo '✅ enroot available' || echo '⚠️  enroot missing (only needed for containers)'
                ls ~/bin/start-ssh-job.bash >/dev/null 2>&1 && echo '✅ interactive-slurm scripts installed' || echo '❌ scripts not found'
            "
        else
            print_error "SSH connection test failed"
            print_info "Please check:"
            print_info "  • HPC login node address: $HPC_LOGIN"
            print_info "  • Username: $HPC_USERNAME"
            print_info "  • SSH key: $SSH_KEY_PATH"
        fi
    fi
}

print_header "Interactive SLURM SSH Sessions - Setup Script"
echo "This script will guide you through the complete setup process."
echo "It will:"
echo "  • Generate SSH keys"
echo "  • Configure HPC access"
echo "  • Set up container options (optional)"
echo "  • Install scripts on HPC cluster"
echo "  • Configure local SSH settings"
echo "  • Set up VSCode integration"
echo

# Validate environment and tools
ENV=$(detect_environment)
validate_tools

# Main setup flow
setup_ssh_key
get_hpc_config
copy_ssh_key_to_hpc
setup_containers
install_hpc_scripts
generate_ssh_config
configure_vscode
test_connection

print_header "Setup Complete!"
print_success "Interactive SLURM SSH Sessions setup completed successfully!"

echo
print_info "Summary of what was configured:"
print_info "  ✅ SSH key generated: $SSH_KEY_PATH"
print_info "  ✅ HPC cluster: $HPC_USERNAME@$HPC_LOGIN"
if [ "$USE_CONTAINERS" = true ]; then
    print_info "  ✅ Container support enabled"
    if [ "$COPY_FROM_SC_PROJECTS" = true ]; then
        print_info "  ✅ Container copied to: $CONTAINER_LOCAL_PATH"
    fi
else
    print_info "  ✅ Direct compute node access (no containers)"
fi
print_info "  ✅ SSH configuration generated"
print_info "  ✅ Scripts installed on HPC cluster"

echo
print_info "Quick start:"
print_info "  1. Open VSCode and install the Remote-SSH extension"
print_info "  2. Press Ctrl/Cmd+Shift+P → 'Remote-SSH: Connect to Host'"
print_info "  3. Choose from your configured hosts:"
print_info "     • slurm-cpu (CPU job, direct access)"
if [ "$ENABLE_RUN_NODES" = true ]; then
    print_info "     • run-rx01 (Run node access, no Slurm job)"
    print_info "     • run-rx02 (Run node access, no Slurm job)"
fi
if [ "$USE_CONTAINERS" = true ]; then
    print_info "     • slurm-cpu-container (CPU job with container)"
fi

echo
print_info "Command line usage:"
print_info "  ssh slurm-cpu    # Connect to CPU job"
if [ "$ENABLE_RUN_NODES" = true ]; then
    print_info "  ssh run-rx01     # Connect directly to Run Node 1"
    print_info "  ssh run-rx02     # Connect directly to Run Node 2"
fi

echo
print_info "For troubleshooting, run these commands on the HPC cluster:"
print_info "  ~/bin/start-ssh-job.bash list    # List running jobs"
print_info "  ~/bin/start-ssh-job.bash cancel  # Cancel all jobs"
print_info "  ~/bin/start-ssh-job.bash help    # Show help"

print_success "Happy computing! 🚀"
