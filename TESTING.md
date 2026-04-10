# 🧪 Testing Interactive SLURM SSH Sessions

This guide walks you through testing the setup to ensure everything works correctly.

## 📋 Prerequisites for Testing

- [ ] You have access to a SLURM HPC cluster
- [ ] You know your cluster's login node hostname/IP
- [ ] You have your username on the cluster
- [ ] Your local machine has `ssh` and `ssh-keygen`

## 🚀 Step-by-Step Testing Guide

### Step 1: **📱 On Your Local Machine** - Run Setup

```bash
git clone https://github.com/aihpi/interactive-slurm.git
cd interactive-slurm
./setup.sh
```

#### Expected Setup Prompts:
1. **HPC Login Node**: Enter your actual cluster hostname
   ```
   HPC Login Node (hostname or IP) [10.130.0.6]: YOUR_ACTUAL_LOGIN_NODE
   ```

2. **Username**: Enter your actual username
   ```
   Your username on the HPC cluster [john.doe]: YOUR_ACTUAL_USERNAME
   ```

3. **Containers**: Choose based on your needs
   ```
   Do you want to use containers? [Y/n]: 
   ```

4. **Container Source** (if yes to containers):
   ```
   Do you have containers in /sc/projects that you want to copy? [Y/n]: 
   Container path to copy: /sc/projects/YOUR_ACTUAL_PATH/container.sqsh
   ```

#### Expected Setup Results:
- ✅ SSH key generated at `~/.ssh/interactive-slurm`
- ✅ Key copied to HPC cluster (you'll enter your password)
- ✅ Scripts installed on cluster
- ✅ SSH config generated
- ✅ VSCode settings updated

### Step 2: **📱 On Your Local Machine** - Test Basic Connection

```bash
# Test CPU job connection
ssh slurm-cpu
```

#### Expected Behavior:
- First connection takes 30 seconds to 5 minutes
- You should see: "Submitted new vscode-remote-cpu job"
- Eventually connects to a compute node
- You get a shell prompt on the compute node

### Step 3: **🖥️ Inside the Connected Session** - Verify Environment

Once connected, test that everything works:

```bash
# Check you're on a compute node (not login node)
hostname

# Check SLURM commands work
squeue --me

# Check available resources
free -h
nvidia-smi  # If using GPU job

# Test container (if using containers)
which python  # Should show container Python if using containers
```

### Step 4: **📱 Local Machine** - Test VSCode Integration

1. Open VSCode
2. Install Remote-SSH extension if not already installed
3. Press `Ctrl/Cmd+Shift+P`
4. Type "Remote-SSH: Connect to Host"
5. Select `slurm-cpu` from the list
6. VSCode should connect to your compute node

### Step 5: **🖥️ On HPC Login Node** - Test Management Commands

SSH directly to your login node and test job management:

```bash
# SSH to login node
ssh your.username@your.login.node

# List running jobs
~/bin/start-ssh-job.bash list

# Should show your vscode-remote jobs
```

## ✅ Success Criteria

Your setup is working correctly if:

- [ ] **Basic Connection**: `ssh slurm-cpu` connects to compute node
- [ ] **Job Submission**: You see job submission messages
- [ ] **SLURM Access**: `squeue` command works from compute node
- [ ] **VSCode Integration**: Can connect via Remote-SSH extension
- [ ] **Job Management**: Can list/cancel jobs from login node
- [ ] **Container Access**: (If using) Container environment is available

## 🐛 Common Test Issues & Solutions

### Issue: "SSH connection test failed" during setup
**Solution:**
```bash
# Test manual SSH connection first
ssh your.username@your.login.node

# If that fails, check:
# - Hostname/IP is correct
# - Username is correct  
# - You can access the cluster normally
```

### Issue: "Connection refused" when testing
**Solution:**
```bash
# Check if job is running
ssh your.login.node "~/bin/start-ssh-job.bash list"

# Cancel and restart
ssh your.login.node "~/bin/start-ssh-job.bash cancel"
ssh slurm-cpu  # Try again
```

### Issue: Connection takes too long (>5 minutes)
**Solution:**
```bash
# Check cluster queue
ssh your.login.node
squeue --me  # See if jobs are pending

# Check cluster resources
sinfo  # See available nodes
```

### Issue: VSCode connection fails
**Solution:**
1. Test command line first: `ssh slurm-cpu`
2. Check VSCode settings: `remote.SSH.connectTimeout` ≥ 300
3. View logs: VSCode → Output → Remote-SSH

## 📝 Test Results Template

After testing, record your results:

```
Testing Results for Interactive SLURM SSH Sessions
==================================================

Cluster: ________________________________
Date: ___________________________________

Setup Phase:
[ ] SSH key generation: _________________ 
[ ] Key copy to cluster: ________________
[ ] Script installation: ________________
[ ] SSH config creation: ________________

Connection Tests:
[ ] ssh slurm-cpu: ______________________
[ ] VSCode connection: __________________

Job Management:
[ ] List jobs: __________________________
[ ] Cancel jobs: _______________________

Container Tests (if applicable):
[ ] Container copied: ___________________
[ ] Container accessible: ______________

Issues Encountered:
___________________________________
___________________________________
___________________________________

Overall Success: [ ] YES [ ] NO
```

## 🎯 Next Steps After Successful Testing

1. **Create your development workflow**
2. **Customize SLURM parameters** in `~/bin/start-ssh-job.bash` if needed
3. **Set up additional SSH hosts** for different resource requirements
4. **Share the setup** with your team members

Happy computing! 🚀
