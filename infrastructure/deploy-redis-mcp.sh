#!/bin/bash

# Redis MCP Server - Complete Stack Deployment
# This script deploys the entire Redis MCP server infrastructure using Bicep
# 
# USAGE: Run this script from the PROJECT ROOT directory
#        ./infrastructure/deploy-redis-mcp.sh                              # Interactive mode
#        ./infrastructure/deploy-redis-mcp.sh -g my-rg -l westus2 -s Balanced_B1  # Non-interactive mode
#        ./infrastructure/deploy-redis-mcp.sh --help                       # Show help

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TEMPLATE_FILE="infrastructure/main.bicep"
PARAMETERS_FILE="infrastructure/main.parameters.json"

# Variables to be set by user input
RESOURCE_GROUP=""
LOCATION=""
REDIS_SKU=""

# Generate unique image tag
generate_image_tag() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    # Try to get git commit hash if available
    if git rev-parse --short HEAD &> /dev/null; then
        local git_hash=$(git rev-parse --short HEAD)
        echo "${timestamp}-${git_hash}"
    else
        echo "${timestamp}"
    fi
}

# Global variable for the image tag (set during execution)
IMAGE_TAG=""

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -s|--redis-sku)
                REDIS_SKU="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  -g, --resource-group NAME    Azure resource group name"
                echo "  -l, --location LOCATION      Azure location (e.g., westus2, eastus)"
                echo "  -s, --redis-sku SKU          Azure Managed Redis SKU (Balanced_B0, Balanced_B1, Balanced_B3, Balanced_B5)"
                echo "  -h, --help                   Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                          # Interactive mode"
                echo "  $0 -g my-rg -l westus2 -s Balanced_B1     # Non-interactive mode"
                echo "  $0 --resource-group my-rg --location eastus --redis-sku Balanced_B3"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Get user input for deployment configuration
configure_infrastructure() {
    # Skip interactive input if all values are already set via command line
    if [[ -n "$RESOURCE_GROUP" && -n "$LOCATION" && -n "$REDIS_SKU" ]]; then
        print_info "Using command-line provided configuration:"
        print_info "  Resource Group: $RESOURCE_GROUP"
        print_info "  Location: $LOCATION"
        print_info "  Redis SKU: $REDIS_SKU"
        return
    fi
    
    print_header "DEPLOYMENT CONFIGURATION"
    
    # Get resource group name
    if [[ -z "$RESOURCE_GROUP" ]]; then
        while [[ -z "$RESOURCE_GROUP" ]]; do
            echo -n -e "${YELLOW}Enter Resource Group name: ${NC}"
            read -r RESOURCE_GROUP
            if [[ -z "$RESOURCE_GROUP" ]]; then
                print_error "Resource Group name cannot be empty"
            elif [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                print_error "Resource Group name can only contain letters, numbers, periods, hyphens, and underscores"
                RESOURCE_GROUP=""
            fi
        done
    fi
    
    # Get location with suggestions
    if [[ -z "$LOCATION" ]]; then
        print_info "Popular Azure locations: eastus, westus2, centralus, westeurope, eastasia, southeastasia"
        while [[ -z "$LOCATION" ]]; do
            echo -n -e "${YELLOW}Enter Azure location (e.g., westus2): ${NC}"
            read -r LOCATION
            if [[ -z "$LOCATION" ]]; then
                print_error "Location cannot be empty"
            elif [[ ! "$LOCATION" =~ ^[a-z0-9]+$ ]]; then
                print_error "Location should be lowercase with no spaces (e.g., westus2, eastus, westeurope)"
                LOCATION=""
            fi
        done
    fi
    
    # Get Redis SKU with options
    if [[ -z "$REDIS_SKU" ]]; then
        print_info "Available Azure Managed Redis SKUs:"
        print_info "  1) Balanced_B0 - (2 vCPU, 0.5 GB RAM) - Development/Testing"
        print_info "  2) Balanced_B1 - (2 vCPU, 1 GB RAM) - Small production workloads"
        print_info "  3) Balanced_B3 - (2 vCPU, 3 GB RAM) - Medium production workloads"
        print_info "  4) Balanced_B5 - (2 vCPU, 6 GB RAM) - Large production workloads"
        print_info "  5) Balanced_B10 - (4 vCPU, 12 GB RAM) - Extra Large production workloads"
        print_info "  6) Balanced_B20 - (8 vCPU, 24 GB RAM) - Huge production workloads"
        print_info "  7) Balanced_B50 - (16 vCPU, 60 GB RAM) - Massive production workloads"

        while [[ -z "$REDIS_SKU" ]]; do
            echo -n -e "${YELLOW}Select Redis SKU (1-7) or enter SKU name: ${NC}"
            read -r sku_choice
            
            case "$sku_choice" in
                1|"Balanced_B0")
                    REDIS_SKU="Balanced_B0"
                    ;;
                2|"Balanced_B1")
                    REDIS_SKU="Balanced_B1"
                    ;;
                3|"Balanced_B3")
                    REDIS_SKU="Balanced_B3"
                    ;;
                4|"Balanced_B5")
                    REDIS_SKU="Balanced_B5"
                    ;;
                5|"Balanced_B10")
                    REDIS_SKU="Balanced_B10"
                    ;;
                6|"Balanced_B20")
                    REDIS_SKU="Balanced_B20"
                    ;;
                7|"Balanced_B50")
                    REDIS_SKU="Balanced_B50"
                    ;;
                "")
                    print_error "SKU selection cannot be empty"
                    ;;
                *)
                    if [[ "$sku_choice" =~ ^Balanced_B(0|1|3|5|10|20|50)$ ]]; then
                        REDIS_SKU="$sku_choice"
                    else
                        print_error "Invalid SKU. Please select 1-7 or enter a valid SKU (Balanced_B0, Balanced_B1, Balanced_B3, Balanced_B5, Balanced_B10, Balanced_B20, Balanced_B50)"
                    fi
                    ;;
            esac
        done
    fi
    
    print_success "Infrastructure configuration complete"
}

# Configure authentication method
configure_authentication() {
    print_step "Configuring MCP Server Authentication..."
    
    print_info "Available authentication methods:"
    print_info "  1) NO-AUTH  - No authentication required (development/testing)"
    print_info "  2) API-KEY  - API key authentication via X-API-Key header"
    print_info "  3) OAUTH    - OAuth JWT token authentication via Authorization header"
    
    AUTH_METHOD=""
    while [[ -z "$AUTH_METHOD" ]]; do
        echo -n -e "${YELLOW}Select authentication method (1-3): ${NC}"
        read -r auth_choice
        
        case "$auth_choice" in
            1|"NO-AUTH"|"no-auth")
                AUTH_METHOD="NO-AUTH"
                API_KEYS=""
                OAUTH_TENANT_ID=""
                OAUTH_CLIENT_ID=""
                OAUTH_SCOPES=""
                print_success "Selected: NO-AUTH (no authentication required)"
                ;;
            2|"API-KEY"|"api-key")
                AUTH_METHOD="API-KEY"
                OAUTH_TENANT_ID=""
                OAUTH_CLIENT_ID=""
                OAUTH_SCOPES=""
                
                # Collect API keys
                print_info "API Key Configuration:"
                print_info "  Enter API keys (comma-separated). You can generate secure keys with: openssl rand -base64 32"
                echo -n -e "${YELLOW}Enter API keys: ${NC}"
                read -r API_KEYS
                
                if [[ -z "$API_KEYS" ]]; then
                    print_error "API keys cannot be empty when using API-KEY authentication"
                    AUTH_METHOD=""
                    continue
                fi
                
                # Count keys
                IFS=',' read -ra KEYS_ARRAY <<< "$API_KEYS"
                KEY_COUNT=${#KEYS_ARRAY[@]}
                print_success "Selected: API-KEY authentication with $KEY_COUNT key(s)"
                ;;
            3|"OAUTH"|"oauth")
                AUTH_METHOD="OAUTH"
                API_KEYS=""
                
                # Collect OAuth configuration
                print_info "OAuth Configuration:"
                
                echo -n -e "${YELLOW}Enter Azure Tenant ID: ${NC}"
                read -r OAUTH_TENANT_ID
                if [[ -z "$OAUTH_TENANT_ID" ]]; then
                    print_error "Tenant ID is required for OAuth authentication"
                    AUTH_METHOD=""
                    continue
                fi
                
                echo -n -e "${YELLOW}Enter Azure Client ID: ${NC}"
                read -r OAUTH_CLIENT_ID
                if [[ -z "$OAUTH_CLIENT_ID" ]]; then
                    print_error "Client ID is required for OAuth authentication"
                    AUTH_METHOD=""
                    continue
                fi
                
                echo -n -e "${YELLOW}Enter required scopes (comma-separated, optional): ${NC}"
                read -r OAUTH_SCOPES
                
                print_success "Selected: OAUTH authentication (tenant: $OAUTH_TENANT_ID, client: $OAUTH_CLIENT_ID)"
                ;;
            "")
                print_error "Authentication method selection cannot be empty"
                ;;
            *)
                print_error "Invalid selection. Please choose 1, 2, or 3"
                ;;
        esac
    done
    
    print_success "Authentication configuration complete"
}

# Confirm deployment configuration
confirm_deployment() {
    echo ""
    print_info "Deployment Configuration:"
    print_info "  Resource Group: $RESOURCE_GROUP"
    print_info "  Location: $LOCATION"
    print_info "  Redis SKU: $REDIS_SKU"
    print_info "  Authentication: $AUTH_METHOD"
    
    case "$AUTH_METHOD" in
        "API-KEY")
            IFS=',' read -ra KEYS_ARRAY <<< "$API_KEYS"
            print_info "  API Keys: ${#KEYS_ARRAY[@]} configured"
            ;;
        "OAUTH")
            print_info "  OAuth Tenant: $OAUTH_TENANT_ID"
            print_info "  OAuth Client: $OAUTH_CLIENT_ID"
            [[ -n "$OAUTH_SCOPES" ]] && print_info "  OAuth Scopes: $OAUTH_SCOPES"
            ;;
    esac
    
    echo ""
    echo -n -e "${YELLOW}Continue with this configuration? (y/N): ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled by user"
        exit 0
    fi
    
    print_success "Configuration confirmed"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check if running from project root
    if [[ ! -f "Dockerfile" || ! -f "infrastructure/main.bicep" ]]; then
        print_error "Script must be run from the project root directory"
        print_error "Expected files: Dockerfile, infrastructure/main.bicep"
        print_info "Current directory: $(pwd)"
        print_info "Usage: ./infrastructure/deploy-complete-stack.sh"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Validate Bicep template
validate_template() {
    print_step "Validating Bicep template..."
    
    if ! az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETERS_FILE" \
        --parameters location="$LOCATION" \
        --parameters redisEnterpriseSku="$REDIS_SKU" > /dev/null 2>&1; then
        
        print_error "Template validation failed"
        az deployment group validate \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$TEMPLATE_FILE" \
            --parameters @"$PARAMETERS_FILE" \
            --parameters location="$LOCATION" \
            --parameters redisEnterpriseSku="$REDIS_SKU"
        exit 1
    fi
    
    print_success "Template validation passed"
}

# Create resource group
create_resource_group() {
    print_step "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_info "Resource group already exists"
    else
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table
        print_success "Resource group created"
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    print_step "Deploying infrastructure stack..."
    
    DEPLOYMENT_NAME="redis-mcp-deployment-$(date +%Y%m%d-%H%M%S)"
    
    print_info "Starting deployment: $DEPLOYMENT_NAME"
    
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETERS_FILE" \
        --parameters location="$LOCATION" \
        --parameters redisEnterpriseSku="$REDIS_SKU" \
        --parameters mcpAuthMethod="$AUTH_METHOD" \
        --parameters mcpApiKeys="$API_KEYS" \
        --parameters oauthTenantId="$OAUTH_TENANT_ID" \
        --parameters oauthClientId="$OAUTH_CLIENT_ID" \
        --parameters oauthRequiredScopes="$OAUTH_SCOPES" \
        --name "$DEPLOYMENT_NAME" \
        --output table
    
    if [ $? -eq 0 ]; then
        print_success "Infrastructure deployment completed"
    else
        print_error "Infrastructure deployment failed"
        exit 1
    fi
}

# Get deployment outputs
get_deployment_outputs() {
    print_step "Getting deployment outputs..."
    
    # Get the latest deployment
    LATEST_DEPLOYMENT=$(az deployment group list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'redis-mcp-deployment')].name" \
        --output tsv | head -1)
    
    if [ -z "$LATEST_DEPLOYMENT" ]; then
        print_error "No deployment found"
        exit 1
    fi
    
    # Get outputs
    OUTPUTS=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LATEST_DEPLOYMENT" \
        --query "properties.outputs")
    
    # Extract specific outputs
    MANAGED_IDENTITY_PRINCIPAL_ID=$(echo $OUTPUTS | jq -r '.managedIdentityPrincipalId.value')
    CONTAINER_REGISTRY_NAME=$(echo $OUTPUTS | jq -r '.containerRegistryName.value')
    REDIS_HOST_NAME=$(echo $OUTPUTS | jq -r '.redisHostName.value')
    CONTAINER_APP_FQDN=$(echo $OUTPUTS | jq -r '.containerAppFqdn.value')
    BUILD_INSTRUCTIONS=$(echo $OUTPUTS | jq -r '.buildInstructions.value')
    
    print_success "Deployment outputs retrieved"
}

# Build and push container image
build_and_push_image() {
    print_step "Building and pushing container image..."
    
    # Generate unique tag for this build
    IMAGE_TAG=$(generate_image_tag)
    print_info "Generated image tag: $IMAGE_TAG"
    
    print_info "Building image with ACR Build..."
    
    # Build using ACR Build with unique tag and also tag as latest
    # (assuming script is run from project root where Dockerfile is located)
    az acr build \
        --registry "$CONTAINER_REGISTRY_NAME" \
        --image "redis-mcp-server:${IMAGE_TAG}" \
        --image "redis-mcp-server:latest" \
        --platform linux/amd64 \
        . \
        --output table
    
    if [ $? -eq 0 ]; then
        print_success "Container image built and pushed successfully"
        print_success "Image tagged as: redis-mcp-server:${IMAGE_TAG}"
        print_success "Image tagged as: redis-mcp-server:latest"
    else
        print_error "Failed to build and push container image"
        exit 1
    fi
}

# Grant Redis access to managed identity
grant_redis_access() {
    print_step "Verifying Redis access policy assignment..."
    
    # Extract Redis name from hostname (remove .redis.cache.windows.net)
    REDIS_NAME=$(echo "$REDIS_HOST_NAME" | cut -d'.' -f1)
    
    print_info "Redis access policy is now configured automatically via Bicep template"
    print_info "Redis instance: $REDIS_NAME"
    print_info "Managed Identity Principal ID: $MANAGED_IDENTITY_PRINCIPAL_ID"
    
    # Verify the access policy assignment exists
    POLICY_EXISTS=$(az redisenterprise database access-policy-assignment show \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$REDIS_NAME" \
        --database-name "default" \
        -n "mcpserveraccess" \
        --query "name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$POLICY_EXISTS" ]; then
        print_success "Redis access policy assignment verified"
    else
        print_error "Redis access policy assignment not found - this may be expected if using older API versions"
        print_info "Access policy is configured in the Bicep template and should be automatically applied"
    fi
}

# Update container app with new image
update_container_app() {
    print_step "Updating container app with real MCP server image..."
    
    CONTAINER_APP_NAME=$(echo $OUTPUTS | jq -r '.containerAppName.value')
    CONTAINER_REGISTRY_LOGIN_SERVER=$(echo $OUTPUTS | jq -r '.containerRegistryLoginServer.value')
    
    print_info "Updating Container App: $CONTAINER_APP_NAME"
    print_info "New Image: $CONTAINER_REGISTRY_LOGIN_SERVER/redis-mcp-server:${IMAGE_TAG}"
    
    # Update container app with the real image using unique tag
    az containerapp update \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --image "$CONTAINER_REGISTRY_LOGIN_SERVER/redis-mcp-server:${IMAGE_TAG}" \
        --output table
    
    if [ $? -eq 0 ]; then
        print_success "Container app updated with real MCP server image"
        print_success "Deployed image: redis-mcp-server:${IMAGE_TAG}"
    else
        print_error "Failed to update container app image"
        exit 1
    fi
}

# Test deployment
test_deployment() {
    print_step "Testing deployment..."
    
    print_info "Container App URL: https://$CONTAINER_APP_FQDN"
    
    # Wait for container app to be ready
    print_info "Waiting for container app to be ready..."
    sleep 30
    
    # Test health endpoint
    if curl -f -s "https://$CONTAINER_APP_FQDN/health" > /dev/null; then
        print_success "Health check passed"
    else
        print_error "Health check failed - container app may still be starting"
        print_info "You can check logs with: az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
    fi
}

# Print deployment summary
print_summary() {
    print_header "DEPLOYMENT SUMMARY"
    
    echo -e "${GREEN}🎉 Redis MCP Server Stack Deployed Successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Deployment Details:${NC}"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Redis SKU: $REDIS_SKU"
    echo "  Deployed Image: redis-mcp-server:${IMAGE_TAG}"
    echo ""
    echo -e "${BLUE}🔗 Service Endpoints:${NC}"
    echo "  MCP Server: https://$CONTAINER_APP_FQDN/message"
    echo "  Redis Host: $REDIS_HOST_NAME"
    echo ""
    echo -e "${BLUE}🔐 Authentication:${NC}"
    case "$AUTH_METHOD" in
        "NO-AUTH")
            echo "  Authentication: DISABLED"
            echo "  Test with: curl https://$CONTAINER_APP_FQDN/health"
            ;;
        "API-KEY")
            IFS=',' read -ra KEYS_ARRAY <<< "$API_KEYS"
            echo "  Authentication: API KEY"
            echo "  API Keys: ${#KEYS_ARRAY[@]} configured"
            echo "  Test with: curl -H \"X-API-Key: your-api-key\" https://$CONTAINER_APP_FQDN/health"
            ;;
        "OAUTH")
            echo "  Authentication: OAUTH"
            echo "  Tenant ID: $OAUTH_TENANT_ID"
            echo "  Client ID: $OAUTH_CLIENT_ID"
            [[ -n "$OAUTH_SCOPES" ]] && echo "  Required Scopes: $OAUTH_SCOPES"
            echo "  Test with: curl -H \"Authorization: Bearer jwt-token\" https://$CONTAINER_APP_FQDN/health"
            ;;
    esac
    echo ""
    echo -e "${BLUE}�🔧 Management Commands:${NC}"
    echo "  View logs: az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
    echo "  Scale app: az containerapp update --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --min-replicas 2 --max-replicas 10"
    echo "  Update image: $BUILD_INSTRUCTIONS"
    echo ""
    echo -e "${BLUE}🧹 Cleanup:${NC}"
    echo "  Delete stack: az group delete --name $RESOURCE_GROUP --yes --no-wait"
    echo ""
    echo -e "${GREEN}✨ Your Redis MCP Server is ready to use!${NC}"
}

# Main execution
# NOTE: This script must be run from the project root directory
main() {
    print_header "REDIS MCP SERVER - COMPLETE STACK DEPLOYMENT"
    
    parse_arguments "$@"
    configure_infrastructure
    configure_authentication   # Configure authentication method and parameters
    confirm_deployment        # Confirm all configuration before deployment
    check_prerequisites
    create_resource_group
    validate_template
    deploy_infrastructure      # Deploys all infrastructure with placeholder image
    get_deployment_outputs     # Gets outputs from deployment
    build_and_push_image      # Builds and pushes the real MCP server image
    grant_redis_access        # Verifies Redis access policies
    update_container_app      # Updates Container App with real image
    test_deployment           # Tests the complete deployment
    print_summary            # Shows deployment summary
}

# Run main function
main "$@"