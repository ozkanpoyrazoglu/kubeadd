#!/bin/bash

KUBECONFIG_FILE="$HOME/.kube/config"
LOCAL_CONFIG_FILE="/Users/ozkanpoyrazoglu/.kube"

show_help() {
    echo "kubeadd - Kubernetes cluster configuration manager"
    echo ""
    echo "Usage:"
    echo "  kubeadd -f <new_kubeconfig_file>  Add new cluster from kubeconfig file"
    echo "  kubeadd -d [context-name]          Delete existing cluster (interactive if no name given)"
    echo "  kubeadd -h                        Show this help"
    echo ""
    echo "Examples:"
    echo "  kubeadd -f ~/Downloads/new-cluster.yaml"
    echo "  kubeadd -d my-cluster"
}

validate_server_url() {
    local server_url="$1"
    echo "🔍 DEBUG: Input URL: '$server_url'"
    echo "🔍 DEBUG: URL length: ${#server_url}"
    
    # More flexible regex for Kubernetes server URLs
    if [[ ! "$server_url" =~ ^https://[a-zA-Z0-9._-]+(\.[a-zA-Z0-9._-]+)*(:[0-9]+)?(/.*)?$ ]]; then
        echo "❌ Invalid server URL format. Expected format: https://server-address[:port][/path]"
        echo "🔍 DEBUG: Regex failed for: '$server_url'"
        return 1
    fi
    echo "✅ Server URL format is valid"
    return 0
}

add_cluster() {
    local new_config_file="$1"
    
    if [[ ! -f "$new_config_file" ]]; then
        echo "❌ Error: File '$new_config_file' not found"
        exit 1
    fi

    # Check if local config exists, otherwise use global
    if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
        KUBECONFIG_FILE="$LOCAL_CONFIG_FILE"
        echo "📁 Using local config file: $LOCAL_CONFIG_FILE"
    else
        echo "📁 Using global config file: $KUBECONFIG_FILE"
    fi

    # Parse new config to get cluster info
    echo "🔍 Analyzing new kubeconfig file..."
    
    # Extract cluster name and server from new config
    local cluster_name=$(yq eval '.clusters[0].name' "$new_config_file" 2>/dev/null)
    local server_url=$(yq eval '.clusters[0].cluster.server' "$new_config_file" 2>/dev/null)
    
    if [[ "$cluster_name" == "null" || "$server_url" == "null" ]]; then
        echo "❌ Error: Could not parse cluster information from '$new_config_file'"
        echo "Make sure the file contains valid kubeconfig format with clusters section"
        exit 1
    fi

    echo "📋 Found cluster information:"
    echo "   Name: $cluster_name"
    echo "   Server: $server_url"
    echo ""

    # Debug: Show what we're validating
    echo "🔍 DEBUG: Validating server URL: '$server_url'"
    
    # Validate server URL
    if ! validate_server_url "$server_url"; then
        echo "❌ Server URL validation failed for: '$server_url'"
        echo "💡 Please check the kubeconfig file format"
        exit 1
    fi

    # Ask for custom cluster name
    echo "🏷️  Cluster naming:"
    read -p "Enter custom name for this cluster (or press Enter to use '$cluster_name'): " custom_name
    
    local original_cluster_name="$cluster_name"
    if [[ -n "$custom_name" ]]; then
        cluster_name="$custom_name"
        echo "✅ Using custom name: $cluster_name"
    else
        echo "✅ Using original name: $cluster_name"
    fi

    # Server confirmation
    echo ""
    echo "🌐 Server validation:"
    echo "   Server URL: $server_url"
    read -p "Is this server URL correct? (y/N): " confirm_server
    
    local new_server_url=""
    if [[ ! "$confirm_server" =~ ^[Yy]$ ]]; then
        read -p "Enter correct server URL: " new_server_url
        if validate_server_url "$new_server_url"; then
            server_url="$new_server_url"
            echo "✅ Updated server URL: $server_url"
        else
            exit 1
        fi
    fi

    # Check if cluster already exists
    if kubectl config get-clusters --kubeconfig="$KUBECONFIG_FILE" 2>/dev/null | grep -q "^$cluster_name$"; then
        echo ""
        echo "⚠️  Warning: Cluster '$cluster_name' already exists in kubeconfig"
        read -p "Do you want to overwrite it? (y/N): " confirm_overwrite

        if [[ ! "$confirm_overwrite" =~ ^[Yy]$ ]]; then
            echo "❌ Operation cancelled"
            exit 1
        fi

        # Remove existing entries before re-adding
        echo "🗑️  Removing existing '$cluster_name' entries..."
        kubectl config delete-cluster "$cluster_name" --kubeconfig="$KUBECONFIG_FILE" >/dev/null 2>&1
        kubectl config delete-context "$cluster_name" --kubeconfig="$KUBECONFIG_FILE" >/dev/null 2>&1
        kubectl config delete-user "$cluster_name" --kubeconfig="$KUBECONFIG_FILE" >/dev/null 2>&1
    fi

    # Create backup
    if [[ -f "$KUBECONFIG_FILE" ]]; then
        cp "$KUBECONFIG_FILE" "${KUBECONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "💾 Backup created: ${KUBECONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Merge configurations
    echo ""
    echo "🔄 Merging configurations..."
    
    # Create temporary file with modified cluster name and server
    local temp_config=$(mktemp)
    cp "$new_config_file" "$temp_config"
    
    # Update cluster, context, and user names to match
    echo "🔧 Updating cluster configuration..."
    
    # Debug: Show temp config structure before modifications
    echo "🔍 DEBUG: Original config structure:"
    yq eval '.clusters[] | .name' "$temp_config"
    yq eval '.contexts[] | .name' "$temp_config" 
    yq eval '.users[] | .name' "$temp_config"
    
    # Update cluster name and server
    echo "🔧 Updating cluster..."
    yq eval ".clusters[0].name = \"$cluster_name\"" -i "$temp_config"
    yq eval ".clusters[0].cluster.server = \"$server_url\"" -i "$temp_config"
    
    # Update contexts - make sure context name, cluster, and user all match
    echo "🔧 Updating context..."
    yq eval ".contexts[0].name = \"$cluster_name\"" -i "$temp_config"
    yq eval ".contexts[0].context.cluster = \"$cluster_name\"" -i "$temp_config"
    yq eval ".contexts[0].context.user = \"$cluster_name\"" -i "$temp_config"
    
    # Update user name
    echo "🔧 Updating user..."
    yq eval ".users[0].name = \"$cluster_name\"" -i "$temp_config"
    
    # Set current context to the new cluster
    echo "🔧 Setting current context..."
    yq eval ".current-context = \"$cluster_name\"" -i "$temp_config"
    
    # Debug: Show temp config structure after modifications
    echo "🔍 DEBUG: Updated config structure:"
    yq eval '.clusters[] | .name' "$temp_config"
    yq eval '.contexts[] | .name' "$temp_config"
    yq eval '.users[] | .name' "$temp_config"

    # Merge configs
    KUBECONFIG="$KUBECONFIG_FILE:$temp_config" kubectl config view --flatten > "${KUBECONFIG_FILE}.tmp"
    mv "${KUBECONFIG_FILE}.tmp" "$KUBECONFIG_FILE"
    
    # Clean up temp file
    rm "$temp_config"

    echo "✅ Successfully added cluster '$cluster_name' to kubeconfig"
    echo "🎯 You can now switch to it with: kubectl config use-context $cluster_name"
}

delete_cluster() {
    local direct_name="$1"

    # Check if local config exists, otherwise use global
    if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
        KUBECONFIG_FILE="$LOCAL_CONFIG_FILE"
        echo "📁 Using local config file: $LOCAL_CONFIG_FILE"
    else
        echo "📁 Using global config file: $KUBECONFIG_FILE"
    fi

    if [[ ! -f "$KUBECONFIG_FILE" ]]; then
        echo "❌ Error: Kubeconfig file not found at $KUBECONFIG_FILE"
        exit 1
    fi

    local cluster_to_delete=""

    if [[ -n "$direct_name" ]]; then
        # Direct name provided — validate it exists
        local clusters=($(kubectl config get-clusters --kubeconfig="$KUBECONFIG_FILE" 2>/dev/null | tail -n +2))
        local found=false
        for cluster in "${clusters[@]}"; do
            if [[ "$cluster" == "$direct_name" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            echo "❌ Cluster '$direct_name' not found in kubeconfig"
            echo ""
            echo "Available clusters:"
            for c in "${clusters[@]}"; do
                echo "   - $c"
            done
            exit 1
        fi

        cluster_to_delete="$direct_name"
    else
        # Interactive selection
        echo "🗑️  Available clusters for deletion:"
        echo ""

        local clusters=($(kubectl config get-clusters --kubeconfig="$KUBECONFIG_FILE" 2>/dev/null | tail -n +2))

        if [[ ${#clusters[@]} -eq 0 ]]; then
            echo "❌ No clusters found in kubeconfig"
            exit 1
        fi

        for i in "${!clusters[@]}"; do
            echo "   $((i+1)). ${clusters[i]}"
        done

        echo ""
        read -p "Enter the number of cluster to delete (or cluster name): " selection

        # Check if selection is a number
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            local index=$((selection-1))
            if [[ $index -ge 0 && $index -lt ${#clusters[@]} ]]; then
                cluster_to_delete="${clusters[index]}"
            else
                echo "❌ Invalid selection number"
                exit 1
            fi
        else
            # Check if it's a valid cluster name
            for cluster in "${clusters[@]}"; do
                if [[ "$cluster" == "$selection" ]]; then
                    cluster_to_delete="$selection"
                    break
                fi
            done

            if [[ -z "$cluster_to_delete" ]]; then
                echo "❌ Cluster '$selection' not found"
                exit 1
            fi
        fi
    fi

    echo ""
    echo "⚠️  You are about to delete cluster: $cluster_to_delete"
    read -p "Are you sure? This action cannot be undone (y/N): " confirm_delete
    
    if [[ ! "$confirm_delete" =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled"
        exit 1
    fi

    # Create backup before deletion
    cp "$KUBECONFIG_FILE" "${KUBECONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backup created: ${KUBECONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    # Delete cluster, context, and user
    kubectl config delete-cluster "$cluster_to_delete" --kubeconfig="$KUBECONFIG_FILE" >/dev/null 2>&1
    kubectl config delete-context "$cluster_to_delete" --kubeconfig="$KUBECONFIG_FILE" >/dev/null 2>&1
    kubectl config delete-user "$cluster_to_delete" --kubeconfig="$KUBECONFIG_FILE" >/dev/null 2>&1

    echo "✅ Successfully deleted cluster '$cluster_to_delete' from kubeconfig"
}

# Check dependencies
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "❌ Error: yq is not installed or not in PATH"
    echo "Please install yq: brew install yq"
    exit 1
fi

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    show_help
    exit 1
fi

case "$1" in
    -f)
        if [[ -z "$2" ]]; then
            echo "❌ Error: -f requires a kubeconfig file path"
            exit 1
        fi
        add_cluster "$2"
        exit 0
        ;;
    -d)
        delete_cluster "$2"
        exit 0
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        echo "❌ Invalid option: $1" >&2
        show_help
        exit 1
        ;;
esac
