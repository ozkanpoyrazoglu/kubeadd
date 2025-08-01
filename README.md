# kubeadd - Kubernetes Cluster Configuration Manager

A simple bash script to manage Kubernetes cluster configurations by adding and removing clusters from your kubeconfig file.

## Features

- Add new Kubernetes clusters from kubeconfig files
- Delete existing clusters from your configuration
- Automatic backup creation before any changes
- Interactive cluster naming and server URL validation
- Support for both local and global kubeconfig files
- URL validation for Kubernetes server endpoints

## Prerequisites

- `kubectl` - Kubernetes command-line tool
- `yq` - YAML processor (install with `brew install yq` on macOS)

## Installation

1. Download the `kubeadd.sh` script
2. Make it executable:
   ```bash
   chmod +x kubeadd.sh
   ```
3. Optionally, move it to your PATH for global access:
   ```bash
   sudo mv kubeadd.sh /usr/local/bin/kubeadd
   ```

### Adding to bashrc/zshrc

To make the script available from anywhere without moving it to `/usr/local/bin`, you can add it to your shell configuration:

1. **For bash users** - Add to `~/.bashrc`:
   ```bash
   echo 'export PATH="$PATH:/path/to/your/kubeadd/directory"' >> ~/.bashrc
   echo 'alias kubeadd="/path/to/your/kubeadd/directory/kubeadd.sh"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. **For zsh users** - Add to `~/.zshrc`:
   ```bash
   echo 'export PATH="$PATH:/path/to/your/kubeadd/directory"' >> ~/.zshrc
   echo 'alias kubeadd="/path/to/your/kubeadd/directory/kubeadd.sh"' >> ~/.zshrc
   source ~/.zshrc
   ```

3. **Or create a simple alias** (recommended):
   ```bash
   # For bash
   echo 'alias kubeadd="~/path/to/kubeadd.sh"' >> ~/.bashrc
   source ~/.bashrc
   
   # For zsh
   echo 'alias kubeadd="~/path/to/kubeadd.sh"' >> ~/.zshrc
   source ~/.zshrc
   ```

After adding the alias, you can use `kubeadd` directly instead of `./kubeadd.sh`.

## Usage

### Add a New Cluster

Add a new cluster from a kubeconfig file:

```bash
./kubeadd.sh -f <path_to_kubeconfig_file>
```

Example:
```bash
./kubeadd.sh -f ~/Downloads/new-cluster.yaml
```

The script will:
1. Parse the cluster information from the provided file
2. Allow you to customize the cluster name
3. Validate the server URL
4. Create a backup of your existing config
5. Merge the new cluster into your kubeconfig

### Delete an Existing Cluster

Remove a cluster from your configuration:

```bash
./kubeadd.sh -d
```

The script will:
1. Show all available clusters
2. Let you select which one to delete
3. Create a backup before deletion
4. Remove the cluster, context, and user from your kubeconfig

### Show Help

Display usage information:

```bash
./kubeadd.sh -h
```

## Configuration

The script automatically detects and uses:
- Local kubeconfig: `~/.kube/config` (if exists)
- Global kubeconfig: `$HOME/.kube/config`

## Backup System

Before making any changes, the script automatically creates timestamped backups:
```
~/.kube/config.backup.YYYYMMDD_HHMMSS
```

## Examples

### Adding a new cluster with custom name

```bash
$ ./kubeadd.sh -f ~/Downloads/production-cluster.yaml
🔍 Analyzing new kubeconfig file...
📋 Found cluster information:
   Name: kubernetes
   Server: https://k8s-prod.example.com:6443

🏷️  Cluster naming:
Enter custom name for this cluster (or press Enter to use 'kubernetes'): production
✅ Using custom name: production

🌐 Server validation:
   Server URL: https://k8s-prod.example.com:6443
Is this server URL correct? (y/N): y

🔄 Merging configurations...
✅ Successfully added cluster 'production' to kubeconfig
🎯 You can now switch to it with: kubectl config use-context production
```

### Deleting a cluster

```bash
$ ./kubeadd.sh -d
🗑️  Available clusters for deletion:

   1. production
   2. staging
   3. development

Enter the number of cluster to delete (or cluster name): 2
⚠️  You are about to delete cluster: staging
Are you sure? This action cannot be undone (y/N): y
💾 Backup created: ~/.kube/config.backup.20250801_143022
✅ Successfully deleted cluster 'staging' from kubeconfig
```

## Troubleshooting

### yq not found
```bash
❌ Error: yq is not installed or not in PATH
Please install yq: brew install yq
```

Install yq using your package manager:
- macOS: `brew install yq`
- Ubuntu/Debian: `sudo apt install yq`
- CentOS/RHEL: `sudo yum install yq` or `sudo dnf install yq`

### Invalid server URL format
The script validates Kubernetes server URLs. Ensure your server URL follows the format:
```
https://server-address[:port][/path]
```

Examples of valid URLs:
- `https://kubernetes.example.com`
- `https://k8s.company.com:6443`
- `https://127.0.0.1:8443`

## License

This project is open source and available under the MIT License.