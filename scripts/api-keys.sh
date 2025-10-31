#!/bin/bash
# Utility script to manage MCP API Keys

set -e

show_help() {
    echo "MCP API Key Management"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  show      Show current API keys"
    echo "  generate  Generate new API keys"
    echo "  help      Show this help"
    echo ""
}

show_keys() {
    AUTH_METHOD=$(azd env get-value MCP_AUTH_METHOD 2>/dev/null || echo "NO-AUTH")
    
    if [ "$AUTH_METHOD" != "API-KEY" ]; then
        echo "❌ Authentication method is not API-KEY (current: $AUTH_METHOD)"
        echo "   Set with: azd env set MCP_AUTH_METHOD API-KEY"
        exit 1
    fi
    
    API_KEYS=$(azd env get-value MCP_API_KEYS 2>/dev/null || echo "")
    
    if [ -z "$API_KEYS" ]; then
        echo "❌ No API keys found in environment"
        echo "   Generate with: $0 generate"
        exit 1
    fi
    
    echo "🔑 Current MCP API Keys:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Split keys and display them
    IFS=',' read -ra KEYS <<< "$API_KEYS"
    for i in "${!KEYS[@]}"; do
        echo "   🔑 API Key $((i+1)): ${KEYS[i]}"
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 Usage examples:"
    echo "   • HTTP Header:  X-API-Key: ${KEYS[0]}"
    echo "   • Query Parameter: ?api_key=${KEYS[0]}"
}

generate_keys() {
    echo "🔐 Generating new API keys..."
    
    # Generate two secure API keys
    API_KEY_1=$(openssl rand -base64 32)
    API_KEY_2=$(openssl rand -base64 32)
    
    # Set the generated keys in the environment
    azd env set MCP_API_KEYS "${API_KEY_1},${API_KEY_2}"
    azd env set MCP_AUTH_METHOD API-KEY
    
    echo ""
    echo "🎉 New API Keys generated successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Your New MCP Server API Keys (save these securely):"
    echo ""
    echo "   🔑 API Key 1: ${API_KEY_1}"
    echo "   🔑 API Key 2: ${API_KEY_2}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⚠️  Important: Store these keys securely. Old keys are now invalid."
    echo ""
    echo "🔄 To apply changes to your deployment, run:"
    echo "   azd provision"
}

# Main script logic
case "${1:-}" in
    "show")
        show_keys
        ;;
    "generate")
        generate_keys
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    "")
        show_keys
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac