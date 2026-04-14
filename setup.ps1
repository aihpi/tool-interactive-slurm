# Interactive SLURM SSH Sessions Setup Script (PowerShell)
# This script guides you through the complete setup process on Windows

$ErrorActionPreference = "Stop"

# Cross-platform home directory
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

# Helper functions
function Print-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Blue
    Write-Host ""
}

function Print-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Print-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Print-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Print-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

# Get user input with default value
function Prompt-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $input = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Default
    }
    return $input
}

# Get yes/no input
function Prompt-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $input = Read-Host "$Prompt $suffix"
        switch -Regex ($input) {
            '^[Yy]' { return $true }
            '^[Nn]' { return $false }
            '^$' { return $Default }
            default { Write-Host "Please answer yes or no." }
        }
    }
}

# Validate required tools
function Test-RequiredTools {
    Print-Header "Validating Required Tools"

    $missingTools = @()
    $warnings = @()

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        $missingTools += "ssh"
    }

    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        $missingTools += "ssh-keygen"
    }

    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
        $missingTools += "scp"
    }

    if ($missingTools.Count -gt 0) {
        Print-Error "Missing required tools: $($missingTools -join ', ')"
        Write-Host "Windows 10/11 should include OpenSSH by default."
        Write-Host "To install it: Settings > Apps > Optional Features > Add a feature > OpenSSH Client"
        exit 1
    }

    Print-Success "Essential tools are available"
}

# Generate SSH key
function Setup-SSHKey {
    Print-Header "SSH Key Setup"

    $sshDir = Join-Path $UserHome ".ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $script:SSHKeyPath = Join-Path $sshDir "interactive-slurm"

    if (Test-Path $script:SSHKeyPath) {
        Print-Warning "SSH key already exists at $($script:SSHKeyPath)"
        $overwrite = Prompt-YesNo "Do you want to overwrite it?" $false

        if (-not $overwrite) {
            Print-Info "Using existing SSH key"
            return
        }
    }

    Print-Info "Generating SSH key at $($script:SSHKeyPath)"
    $dateStamp = Get-Date -Format "yyyyMMdd"
    # Empty string passphrase: PowerShell needs @() trick or just pass empty string directly
    ssh-keygen -t ed25519 -f $script:SSHKeyPath -N '""' -C "interactive-slurm-$dateStamp"

    if ($LASTEXITCODE -eq 0) {
        Print-Success "SSH key generated successfully"
        Write-Host ""
        Write-Host "Public key content:" -ForegroundColor Blue
        Get-Content "$($script:SSHKeyPath).pub"
        Write-Host ""
    }
    else {
        Print-Error "Failed to generate SSH key"
        exit 1
    }
}

# Get HPC configuration
function Get-HPCConfig {
    Print-Header "HPC Cluster Configuration"

    Write-Host "Please provide your HPC cluster details:"
    Write-Host ""

    $script:HPCLogin = Prompt-WithDefault "HPC Login Node (hostname or IP)" "10.130.0.6"
    $script:HPCUsername = Prompt-WithDefault "Your username on the HPC cluster" "john.doe"
    $script:EnableRunNodes = Prompt-YesNo "Generate direct SSH hosts for Run Nodes?" $true

    if ($script:EnableRunNodes) {
        $script:RunNode1 = Prompt-WithDefault "Run Node 1 hostname" "rx01.hpc.sci.hpi.de"
        $script:RunNode2 = Prompt-WithDefault "Run Node 2 hostname" "rx02.hpc.sci.hpi.de"
    }
    else {
        $script:RunNode1 = ""
        $script:RunNode2 = ""
    }

    Print-Info "Configuration set:"
    Print-Info "  Login Node: $($script:HPCLogin)"
    Print-Info "  Username: $($script:HPCUsername)"
    if ($script:EnableRunNodes) {
        Print-Info "  Run Nodes: $($script:RunNode1), $($script:RunNode2)"
    }
}

# Copy SSH key to HPC (ssh-copy-id doesn't exist on Windows)
function Copy-SSHKeyToHPC {
    Print-Header "Copying SSH Key to HPC Cluster"

    Print-Info "Copying public key to $($script:HPCUsername)@$($script:HPCLogin)"
    Print-Warning "You may be prompted for your HPC password"

    $pubKeyContent = (Get-Content "$($script:SSHKeyPath).pub" -Raw).Trim()

    # ssh-copy-id does not exist on Windows, so we do it manually
    # Use a single ssh command that reads the key inline
    try {
        ssh "$($script:HPCUsername)@$($script:HPCLogin)" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        Print-Success "SSH key copied successfully"
    }
    catch {
        Print-Error "Failed to copy SSH key"
        Print-Info "You can manually copy the key later by running:"
        Print-Info "  type `"$($script:SSHKeyPath).pub`" | ssh $($script:HPCUsername)@$($script:HPCLogin) `"cat >> ~/.ssh/authorized_keys`""

        $continueSetup = Prompt-YesNo "Continue with setup anyway?" $true
        if (-not $continueSetup) {
            exit 1
        }
    }
}

# Container configuration
function Setup-Containers {
    Print-Header "Container Configuration"

    $script:UseContainers = Prompt-YesNo "Do you want to use containers? (experimental)" $true

    if ($script:UseContainers) {
        Write-Host ""
        Print-Info "Container setup options:"

        $script:CopyFromSCProjects = Prompt-YesNo "Do you have containers in /sc/projects that you want to copy?" $true

        if ($script:CopyFromSCProjects) {
            Write-Host ""
            Print-Info "Available .sqsh files in /sc/projects:"
            Write-Host "Please check what's available and specify the paths you want to copy."
            Write-Host "Example paths:"
            Write-Host "  /sc/projects/sci-aisc/sqsh-files/pytorch_ssh.sqsh"
            Write-Host "  /sc/projects/shared/ubuntu22-cuda.sqsh"
            Write-Host ""

            $script:ContainerSourcePath = Prompt-WithDefault "Container path to copy (full path)" "/sc/projects/sci-aisc/sqsh-files/pytorch_ssh.sqsh"
            $containerFilename = Split-Path $script:ContainerSourcePath -Leaf
            # This path is on the remote HPC, so use Unix-style
            $script:ContainerLocalPath = "~/$containerFilename"

            Print-Info "Will copy: $($script:ContainerSourcePath)"
            Print-Info "To: $($script:ContainerLocalPath)"
        }
        else {
            $script:ContainerLocalPath = Prompt-WithDefault "Remote container path (in your home directory on HPC)" "~/my-container.sqsh"
        }

        Print-Success "Container configuration complete"
    }
    else {
        Print-Info "No containers will be used - direct compute node access"
        $script:ContainerLocalPath = ""
    }
}

# Install scripts on HPC
function Install-HPCScripts {
    Print-Header "Installing Scripts on HPC Cluster"

    Print-Info "Connecting to HPC cluster to install scripts..."

    # Create bin directory and add to PATH on HPC
    Print-Info "Creating ~/bin on HPC..."
    $pathExportLine = 'export PATH="$HOME/bin:$PATH"'
    ssh -i $script:SSHKeyPath "$($script:HPCUsername)@$($script:HPCLogin)" @"
mkdir -p ~/bin
if ! grep -Fqx '$pathExportLine' ~/.bashrc 2>/dev/null; then
    echo '$pathExportLine' >> ~/.bashrc
fi
"@

    # Copy scripts from bin/ directory
    Print-Info "Copying interactive-slurm scripts..."

    $binDir = Join-Path $PSScriptRoot "bin"
    if (-not (Test-Path $binDir)) {
        Print-Error "bin/ directory not found at $binDir"
        Print-Info "Make sure you run this script from the project root directory."
        exit 1
    }

    $binFiles = Get-ChildItem -Path $binDir -File
    foreach ($file in $binFiles) {
        Print-Info "  Copying $($file.Name)..."
        scp -i $script:SSHKeyPath $file.FullName "$($script:HPCUsername)@$($script:HPCLogin):~/bin/$($file.Name)"
    }

    Print-Info "Setting script permissions..."
    ssh -i $script:SSHKeyPath "$($script:HPCUsername)@$($script:HPCLogin)" "chmod +x ~/bin/*.bash ~/bin/*.sh 2>/dev/null; chmod +x ~/bin/start-ssh-job.bash ~/bin/ssh-session.bash ~/bin/incontainer-setup.sh 2>/dev/null"

    Print-Info "Verifying script permissions..."
    ssh -i $script:SSHKeyPath "$($script:HPCUsername)@$($script:HPCLogin)" "ls -la ~/bin/*.bash ~/bin/*.sh 2>/dev/null | head -5"

    # Copy container if specified
    if ($script:UseContainers -and $script:CopyFromSCProjects) {
        Print-Info "Copying container file..."
        try {
            ssh -i $script:SSHKeyPath "$($script:HPCUsername)@$($script:HPCLogin)" "cp '$($script:ContainerSourcePath)' '$($script:ContainerLocalPath)'"
        }
        catch {
            Print-Warning "Failed to copy container file. You may need to copy it manually later."
        }
    }

    Print-Success "Scripts installed on HPC cluster"
}

# Clean existing Interactive SLURM entries from SSH config
function Remove-ExistingSLURMConfig {
    param([string]$ConfigFile)

    if (-not (Test-Path $ConfigFile)) {
        return
    }

    $lines = Get-Content $ConfigFile
    $newLines = @()
    $inSlurmSection = $false

    foreach ($line in $lines) {
        if ($line -match "=== Interactive SLURM SSH Sessions") {
            $inSlurmSection = $true
            continue
        }
        if ($line -match "=== End Interactive SLURM SSH Sessions ===") {
            $inSlurmSection = $false
            continue
        }
        if (-not $inSlurmSection) {
            $newLines += $line
        }
    }

    Set-Content -Path $ConfigFile -Value $newLines
}

# Generate SSH config
function New-SSHConfig {
    Print-Header "Generating SSH Configuration"

    $sshDir = Join-Path $UserHome ".ssh"
    $sshConfigFile = Join-Path $sshDir "config"
    $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # Backup existing config
    if (Test-Path $sshConfigFile) {
        $backupFile = Join-Path $sshDir "config.backup.$dateStamp"
        Print-Info "Backing up existing SSH config to $backupFile"
        Copy-Item $sshConfigFile $backupFile
    }

    # Clean existing Interactive SLURM entries
    if (Test-Path $sshConfigFile) {
        Print-Info "Removing existing Interactive SLURM SSH entries..."
        Remove-ExistingSLURMConfig $sshConfigFile
    }

    # Build config content
    $configDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Use forward slashes in the SSH config for the key path, since OpenSSH on Windows accepts them
    $sshKeyPathForConfig = $script:SSHKeyPath -replace '\\', '/'

    $configContent = @"

# === Interactive SLURM SSH Sessions (generated $configDate) ===

# Direct compute node access (no container)
Host slurm-cpu
    HostName $($script:HPCLogin)
    User $($script:HPCUsername)
    IdentityFile $sshKeyPathForConfig
    ConnectTimeout 60
    ProxyCommand ssh $($script:HPCLogin) -l $($script:HPCUsername) -i $sshKeyPathForConfig "bash ~/bin/start-ssh-job.bash cpu"
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

"@

    if ($script:EnableRunNodes) {
        $configContent += @"
# Direct run node access (no Slurm job required)
Host run-rx01
    HostName $($script:RunNode1)
    User $($script:HPCUsername)
    IdentityFile $sshKeyPathForConfig
    ConnectTimeout 60
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host run-rx02
    HostName $($script:RunNode2)
    User $($script:HPCUsername)
    IdentityFile $sshKeyPathForConfig
    ConnectTimeout 60
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

"@
    }

    if ($script:UseContainers) {
        $configContent += @"
# Container-based access
Host slurm-cpu-container
    HostName $($script:HPCLogin)
    User $($script:HPCUsername)
    IdentityFile $sshKeyPathForConfig
    ConnectTimeout 60
    ProxyCommand ssh $($script:HPCLogin) -l $($script:HPCUsername) -i $sshKeyPathForConfig "bash ~/bin/start-ssh-job.bash cpu $($script:ContainerLocalPath)"
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

"@
    }

    $configContent += @"
# === End Interactive SLURM SSH Sessions ===

"@

    # Append to config file
    Add-Content -Path $sshConfigFile -Value $configContent

    Print-Success "SSH configuration generated"
    Print-Info "Available SSH hosts:"
    Print-Info "  - ssh slurm-cpu    (CPU job, direct access)"
    if ($script:EnableRunNodes) {
        Print-Info "  - ssh run-rx01     (Run node access, no Slurm job)"
        Print-Info "  - ssh run-rx02     (Run node access, no Slurm job)"
    }

    if ($script:UseContainers) {
        Print-Info "  - ssh slurm-cpu-container (CPU job with container)"
    }
}

# Configure VSCode
function Set-VSCodeConfig {
    Print-Header "VSCode Configuration"

    # Cross-platform VSCode settings directory
    if ($env:APPDATA) {
        # Windows
        $vsCodeSettingsDir = Join-Path $env:APPDATA "Code\User"
    } elseif ($IsMacOS) {
        # macOS
        $vsCodeSettingsDir = Join-Path $UserHome "Library/Application Support/Code/User"
    } else {
        # Linux
        $vsCodeSettingsDir = Join-Path $UserHome ".config/Code/User"
    }

    if (Test-Path $vsCodeSettingsDir) {
        Print-Info "Found VSCode settings directory: $vsCodeSettingsDir"

        $settingsFile = Join-Path $vsCodeSettingsDir "settings.json"

        $configureVSCode = Prompt-YesNo "Configure VSCode settings for remote SSH?" $true

        if ($configureVSCode) {
            # Create backup
            if (Test-Path $settingsFile) {
                $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
                Copy-Item $settingsFile "$settingsFile.backup.$dateStamp"
            }

            # Read or create settings
            if (Test-Path $settingsFile) {
                try {
                    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                }
                catch {
                    $settings = [PSCustomObject]@{}
                }
            }
            else {
                $settings = [PSCustomObject]@{}
            }

            # Add remote SSH timeout
            if (-not ($settings.PSObject.Properties.Name -contains 'remote.SSH.connectTimeout')) {
                $settings | Add-Member -NotePropertyName 'remote.SSH.connectTimeout' -NotePropertyValue 300
            }
            else {
                $settings.'remote.SSH.connectTimeout' = 300
            }

            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile

            Print-Success "VSCode settings configured"
        }
    }
    else {
        Print-Warning "VSCode settings directory not found at $vsCodeSettingsDir"
        Print-Info "If VSCode is installed, the settings may be in a different location."
    }

    Print-Info "VSCode Remote-SSH Extension:"
    Print-Info "  1. Install the 'Remote - SSH' extension from the marketplace"
    Print-Info "  2. Use Ctrl+Shift+P and search 'Remote-SSH: Connect to Host'"
    Print-Info "  3. Select one of your configured hosts (slurm-cpu, run-rx01, run-rx02, etc.)"
}

# Test connection
function Test-HPCConnection {
    Print-Header "Testing Connection"

    $testConnection = Prompt-YesNo "Test SSH connection to HPC cluster?" $true

    if ($testConnection) {
        Print-Info "Testing basic SSH connection..."

        $result = ssh -i $script:SSHKeyPath -o ConnectTimeout=10 -o BatchMode=yes "$($script:HPCUsername)@$($script:HPCLogin)" "echo 'SSH connection successful'" 2>$null

        if ($LASTEXITCODE -eq 0) {
            Print-Success "SSH connection test passed"

            Print-Info "Testing SLURM availability..."
            $slurmResult = ssh -i $script:SSHKeyPath -o ConnectTimeout=10 "$($script:HPCUsername)@$($script:HPCLogin)" "command -v squeue >/dev/null && echo 'SLURM available'" 2>$null

            if ($slurmResult -match "SLURM available") {
                Print-Success "SLURM is available on the cluster"
            }
            else {
                Print-Warning "SLURM may not be available or not in PATH"
            }

            Print-Info "Testing required tools on cluster..."
            ssh -i $script:SSHKeyPath -o ConnectTimeout=10 "$($script:HPCUsername)@$($script:HPCLogin)" @"
echo 'Testing tools on HPC cluster:'
command -v nc >/dev/null && echo '[OK] netcat (nc) available' || echo '[MISSING] netcat (nc) missing'
command -v sshd >/dev/null && echo '[OK] sshd available' || echo '[MISSING] sshd missing'
command -v enroot >/dev/null && echo '[OK] enroot available' || echo '[WARN] enroot missing (only needed for containers)'
ls ~/bin/start-ssh-job.bash >/dev/null 2>&1 && echo '[OK] interactive-slurm scripts installed' || echo '[MISSING] scripts not found'
"@
        }
        else {
            Print-Error "SSH connection test failed"
            Print-Info "Please check:"
            Print-Info "  - HPC login node address: $($script:HPCLogin)"
            Print-Info "  - Username: $($script:HPCUsername)"
            Print-Info "  - SSH key: $($script:SSHKeyPath)"
        }
    }
}

# === Main Script ===

Print-Header "Interactive SLURM SSH Sessions - Setup Script (Windows)"
Write-Host "This script will guide you through the complete setup process."
Write-Host "It will:"
Write-Host "  - Generate SSH keys"
Write-Host "  - Configure HPC access"
Write-Host "  - Set up container options (optional)"
Write-Host "  - Install scripts on HPC cluster"
Write-Host "  - Configure local SSH settings"
Write-Host "  - Set up VSCode integration"
Write-Host ""

# Main setup flow
Test-RequiredTools
Setup-SSHKey
Get-HPCConfig
Copy-SSHKeyToHPC
Setup-Containers
Install-HPCScripts
New-SSHConfig
Set-VSCodeConfig
Test-HPCConnection

Print-Header "Setup Complete!"
Print-Success "Interactive SLURM SSH Sessions setup completed successfully!"

Write-Host ""
Print-Info "Summary of what was configured:"
Print-Info "  [OK] SSH key generated: $($script:SSHKeyPath)"
Print-Info "  [OK] HPC cluster: $($script:HPCUsername)@$($script:HPCLogin)"
if ($script:UseContainers) {
    Print-Info "  [OK] Container support enabled"
    if ($script:CopyFromSCProjects) {
        Print-Info "  [OK] Container copied to: $($script:ContainerLocalPath)"
    }
}
else {
    Print-Info "  [OK] Direct compute node access (no containers)"
}
Print-Info "  [OK] SSH configuration generated"
Print-Info "  [OK] Scripts installed on HPC cluster"

Write-Host ""
Print-Info "Quick start:"
Print-Info "  1. Open VSCode and install the Remote-SSH extension"
Print-Info "  2. Press Ctrl+Shift+P -> 'Remote-SSH: Connect to Host'"
Print-Info "  3. Choose from your configured hosts:"
Print-Info "     - slurm-cpu (CPU job, direct access)"
if ($script:EnableRunNodes) {
    Print-Info "     - run-rx01 (Run node access, no Slurm job)"
    Print-Info "     - run-rx02 (Run node access, no Slurm job)"
}
if ($script:UseContainers) {
    Print-Info "     - slurm-cpu-container (CPU job with container)"
}

Write-Host ""
Print-Info "Command line usage:"
Print-Info "  ssh slurm-cpu    # Connect to CPU job"
if ($script:EnableRunNodes) {
    Print-Info "  ssh run-rx01     # Connect directly to Run Node 1"
    Print-Info "  ssh run-rx02     # Connect directly to Run Node 2"
}

Write-Host ""
Print-Info "For troubleshooting, run these commands on the HPC cluster:"
Print-Info "  ~/bin/start-ssh-job.bash list    # List running jobs"
Print-Info "  ~/bin/start-ssh-job.bash cancel  # Cancel all jobs"
Print-Info "  ~/bin/start-ssh-job.bash help    # Show help"

Print-Success "Happy computing!"
