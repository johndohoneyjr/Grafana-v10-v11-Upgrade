#!/bin/bash


set -e

echo "🚀 Grafana Test Environment Deployment"
echo "======================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if AZD is installed
    if ! command -v azd &> /dev/null; then
        print_error "Azure Developer CLI (azd) is not installed. Please install it first."
        echo "Visit: https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to get SSH public key
get_ssh_key() {
    print_info "Configuring SSH key..."
    
    SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
    
    if [ ! -f "$SSH_KEY_PATH" ]; then
        print_warning "SSH key not found at $SSH_KEY_PATH"
        echo "Generating new SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N "" -C "azd-grafana-test-$(date +%Y%m%d)"
    fi
    
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH")
    print_status "SSH key configured"
}

# Function to update parameters file with SSH key
update_parameters() {
    print_info "Updating deployment parameters..."
    
    # Create a temporary parameters file with the SSH key
    jq --arg ssh_key "$SSH_PUBLIC_KEY" \
       '.parameters.sshPublicKey.value = $ssh_key' \
       infra/main.parameters.json > infra/main.parameters.tmp.json
    
    mv infra/main.parameters.tmp.json infra/main.parameters.json
    
    print_status "Parameters updated"
}

# Function to initialize AZD environment
initialize_azd() {
    print_info "Initializing Azure Developer CLI environment..."
    
    # Set environment name
    ENVIRONMENT_NAME="${1:-graftest-$(date +%Y%m%d-%H%M)}"
    
    # Initialize if not already done
    if [ ! -d ".azure" ]; then
        azd init --environment "$ENVIRONMENT_NAME"
    fi
    
    # Set subscription if provided
    if [ -n "$2" ]; then
        azd env set AZURE_SUBSCRIPTION_ID "$2"
    fi
    
    print_status "AZD environment initialized: $ENVIRONMENT_NAME"
    export AZURE_ENV_NAME="$ENVIRONMENT_NAME"
}

# Function to provision infrastructure
provision_infrastructure() {
    print_info "Provisioning Azure infrastructure..."
    print_warning "This may take 15-20 minutes..."
    
    # Preview the deployment first
    echo "Previewing deployment..."
    azd provision --preview
    
    # Ask for confirmation
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled by user"
        exit 1
    fi
    
    # Provision infrastructure
    azd provision
    
    print_status "Infrastructure provisioned successfully"
}

# Function to configure monitoring and alerts
configure_monitoring() {
    print_info "Configuring monitoring and alerts..."
    
    # Run the advanced alerts script
    chmod +x scripts/create-advanced-alerts.sh
    scripts/create-advanced-alerts.sh
    
    print_status "Monitoring and alerts configured"
}

# Function to display summary
display_summary() {
    print_info "Deployment Summary"
    echo "=================="
    
    # Load environment variables
    if [ -f ".azure/${AZURE_ENV_NAME}/.env" ]; then
        source .azure/${AZURE_ENV_NAME}/.env
        
        echo ""
        echo "🔗 Resources Created:"
        echo "   • Grafana Instance: $GRAFANA_INSTANCE_NAME"
        echo "   • Grafana URL: $GRAFANA_ENDPOINT"
        echo "   • AKS Cluster: $AKS_CLUSTER_NAME"
        echo "   • Resource Group: $AZURE_RESOURCE_GROUP_NAME"
        echo "   • Azure Monitor Workspace: $AZURE_MONITOR_WORKSPACE_NAME"
        echo ""
        echo "📊 Monitoring Setup:"
        echo "   • Azure Monitor alerts: 3 rules"
        echo "   • Prometheus alerts: 5 rules"
        echo "   • Grafana alerts: 5 rules"
        echo "   • Test workloads: 3 deployments"
        echo ""
        echo "🧪 Testing Commands:"
        echo "   # Get AKS credentials:"
        echo "   az aks get-credentials --resource-group $AZURE_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME"
        echo ""
        echo "   # Check pods:"
        echo "   kubectl get pods --all-namespaces"
        echo ""
        echo "   # Trigger CPU alert:"
        echo "   kubectl scale deployment cpu-stress-test --replicas=3 -n monitoring"
        echo ""
        echo "   # Trigger memory alert:"
        echo "   kubectl scale deployment memory-leak-simulator --replicas=2 -n monitoring"
        echo ""
        echo "   # Check Azure Monitor alerts:"
        echo "   az monitor metrics alert list --resource-group $AZURE_RESOURCE_GROUP_NAME"
        echo ""
        echo "🔧 Cleanup Command:"
        echo "   azd down --force --purge"
        echo ""
        
        print_status "Deployment completed successfully!"
        print_info "Access Grafana at: $GRAFANA_ENDPOINT"
    else
        print_error "Could not load environment variables"
    fi
}

# Main execution flow
main() {
    echo "Starting deployment process..."
    echo ""
    
    # Parse command line arguments
    ENVIRONMENT_NAME="$1"
    SUBSCRIPTION_ID="$2"
    
    if [ -z "$ENVIRONMENT_NAME" ]; then
        ENVIRONMENT_NAME="graftest-$(date +%Y%m%d-%H%M)"
        print_info "Using default environment name: $ENVIRONMENT_NAME"
    fi
    
    # Execute deployment steps
    check_prerequisites
    get_ssh_key
    update_parameters
    initialize_azd "$ENVIRONMENT_NAME" "$SUBSCRIPTION_ID"
    provision_infrastructure
    
    # The setup-alerts.sh script runs automatically via the postprovision hook
    print_info "Post-provision setup completed via AZD hooks"
    
    # Configure additional monitoring
    configure_monitoring
    
    # Display summary
    echo ""
    display_summary
}

# Help function
show_help() {
    echo "Grafana Test Environment Deployment Script"
    echo ""
    echo "Usage: $0 [ENVIRONMENT_NAME] [SUBSCRIPTION_ID]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT_NAME    Name for the AZD environment (optional)"
    echo "  SUBSCRIPTION_ID     Azure subscription ID (optional)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 my-test-env                       # Custom environment name"
    echo "  $0 my-test-env 12345678-1234-5678... # Custom name and subscription"
    echo ""
    echo "Prerequisites:"
    echo "  - Azure CLI installed and logged in"
    echo "  - Azure Developer CLI (azd) installed"
    echo "  - Sufficient permissions in Azure subscription"
    echo ""
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Run main function
main "$@"
