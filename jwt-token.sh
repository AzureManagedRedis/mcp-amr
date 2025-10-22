#!/bin/bash

# Set your variables here
TENANT_ID="${TENANT_ID:-$(az account show --query tenantId -o tsv)}"
TEST_CLIENT_ID="${TEST_CLIENT_ID:-7e7d9666-3415-4e29-8450-e7af1d38af6f}"  # Your client ID from the error
APP_ID="${APP_ID:-68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e}"  # Your Redis MCP Server app ID

echo "Using:"
echo "  Tenant ID: $TENANT_ID"
echo "  Test Client ID: $TEST_CLIENT_ID"
echo "  Target App ID: $APP_ID"
echo ""

function create_jwt_assertion() {
    # Use base64-encoded thumbprint for JWT x5t claim (this is what Azure AD expects)
    local thumbprint_for_jwt="${CERT_THUMBPRINT_B64:-$CERT_THUMBPRINT}"
    local header='{"alg":"RS256","typ":"JWT","x5t":"'$thumbprint_for_jwt'"}'
    local now=$(date +%s)
    local exp=$((now + 300))
    local jti=$(uuidgen)
    local payload='{"aud":"https://login.microsoftonline.com/'$TENANT_ID'/oauth2/v2.0/token","exp":'$exp',"iss":"'$TEST_CLIENT_ID'","jti":"'$jti'","nbf":'$now',"sub":"'$TEST_CLIENT_ID'"}'
    
    # Debug output (to stderr so it doesn't interfere with JWT output)
    >&2 echo "DEBUG: Using thumbprint for JWT x5t claim: $thumbprint_for_jwt"
    >&2 echo "DEBUG: Header: $header"
    >&2 echo "DEBUG: Payload: $payload"
    
    # Base64 encode header and payload (URL-safe, no padding)
    local encoded_header=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-')
    local encoded_payload=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create signature
    local unsigned_token="$encoded_header.$encoded_payload"
    local signature=$(echo -n "$unsigned_token" | openssl dgst -sha256 -sign test-private.key -binary | base64 | tr -d '=' | tr '/+' '_-')
    
    # Output only the JWT token
    echo "$unsigned_token.$signature"
}


# First, let's check what certificates are currently registered
echo "Checking currently registered certificates..."
az ad app show --id $TEST_CLIENT_ID --query "keyCredentials[].{thumbprint:customKeyIdentifier, displayName:displayName}" -o table

# Extract certificate from your combined file if it exists
if [ -f "combined-cert-1.pem" ]; then
    echo "Extracting certificate from combined-cert-1.pem..."
    openssl x509 -in combined-cert-1.pem -out test-cert.pem
    
    # Extract private key
    if grep -q "BEGIN RSA PRIVATE KEY" combined-cert-1.pem; then
        sed -n '/-----BEGIN RSA PRIVATE KEY-----/,/-----END RSA PRIVATE KEY-----/p' combined-cert-1.pem > test-private.key
    elif grep -q "BEGIN PRIVATE KEY" combined-cert-1.pem; then
        sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' combined-cert-1.pem > test-private.key
    fi
    
    echo "✅ Certificate and key extracted"
else
    echo "❌ combined-cert-1.pem not found"
    echo ""
    echo "You have existing registered certificates with thumbprint: dcbd1516a5d6c1317e431424361ba5fd851a751b"
    echo "Do you have the private key for one of those certificates?"
    echo "If so, please:"
    echo "1. Extract the certificate: openssl x509 -in your-cert-file.pem -out test-cert.pem"
    echo "2. Extract the private key: openssl pkey -in your-cert-file.pem -out test-private.key"
    echo "3. Make sure combined-cert-1.pem contains both certificate and private key"
    exit 1
fi

# Upload the certificate to Azure AD
echo "Uploading certificate to Azure AD app..."
CERT_UPLOAD_RESULT=$(az ad app credential reset --id $TEST_CLIENT_ID --cert @test-cert.pem --append 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "✅ Certificate uploaded successfully"
else
    echo "❌ Failed to upload certificate, trying to add it..."
    # Try alternative method
    az ad app credential reset --id $TEST_CLIENT_ID --cert @test-cert.pem --append
fi

# Calculate the correct thumbprint
CERT_THUMBPRINT=$(openssl x509 -in test-cert.pem -noout -fingerprint -sha1 | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
echo "Calculated certificate thumbprint: $CERT_THUMBPRINT"

# Verify the certificate is now registered
echo "Verifying certificate registration..."
REGISTERED_CERTS=$(az ad app show --id $TEST_CLIENT_ID --query "keyCredentials[].customKeyIdentifier" -o tsv)
echo "Registered certificate thumbprints (hex format):"

CERT_FOUND=false
for cert_hex in $REGISTERED_CERTS; do
    if [ ! -z "$cert_hex" ]; then
        # Convert hex to readable format (lowercase)
        thumbprint_readable=$(echo "$cert_hex" | tr '[:upper:]' '[:lower:]')
        echo "  - Hex: $cert_hex"
        echo "    Readable: $thumbprint_readable"
        
        if [ "$thumbprint_readable" = "$CERT_THUMBPRINT" ]; then
            echo "    ✅ This matches our certificate!"
            CERT_FOUND=true
            # Use the Azure AD format for JWT (base64-encoded hex)
            CERT_THUMBPRINT_B64=$(echo "$cert_hex" | xxd -r -p | base64 -w 0 | tr -d '=')
            echo "    Base64 format for JWT: $CERT_THUMBPRINT_B64"
        fi
    fi
done

if [ "$CERT_FOUND" = false ]; then
    echo "❌ Our certificate thumbprint ($CERT_THUMBPRINT) not found in registered certificates!"
    echo "Trying to use the most recent registered certificate..."
    # Use the last registered certificate
    LATEST_CERT_HEX=$(echo "$REGISTERED_CERTS" | tail -n 1)
    if [ ! -z "$LATEST_CERT_HEX" ]; then
        CERT_THUMBPRINT=$(echo "$LATEST_CERT_HEX" | tr '[:upper:]' '[:lower:]')
        CERT_THUMBPRINT_B64=$(echo "$LATEST_CERT_HEX" | xxd -r -p | base64 -w 0 | tr -d '=')
        echo "Using registered certificate thumbprint: $CERT_THUMBPRINT"
        echo "Base64 format: $CERT_THUMBPRINT_B64"
    fi
fi

# Alternative approach: Use an existing registered certificate
echo ""
echo "Alternative: Using existing registered certificate..."
if [ ! -z "$REGISTERED_CERTS" ]; then
    # Get the first registered certificate
    EXISTING_CERT_HEX=$(echo "$REGISTERED_CERTS" | head -n 1)
    EXISTING_CERT_THUMBPRINT=$(echo "$EXISTING_CERT_HEX" | tr '[:upper:]' '[:lower:]')
    EXISTING_CERT_B64=$(echo "$EXISTING_CERT_HEX" | xxd -r -p | base64 -w 0 | tr -d '=')
    
    echo "Using existing certificate:"
    echo "  Hex: $EXISTING_CERT_HEX"
    echo "  Thumbprint: $EXISTING_CERT_THUMBPRINT"
    echo "  Base64: $EXISTING_CERT_B64"
    
    # Override our variables to use the existing cert
    CERT_THUMBPRINT="$EXISTING_CERT_THUMBPRINT"
    CERT_THUMBPRINT_B64="$EXISTING_CERT_B64"
fi

# Now create and test the JWT
echo ""
echo "Creating JWT with thumbprint: $CERT_THUMBPRINT"
echo "Base64 format for x5t: ${CERT_THUMBPRINT_B64:-$CERT_THUMBPRINT}"
jwt_token=$(create_jwt_assertion)
echo "Generated JWT: $jwt_token"

# Validate the JWT structure
echo ""
echo "JWT Validation:"
jwt_parts=$(echo "$jwt_token" | tr '.' '\n' | wc -l)
echo "  JWT parts count: $jwt_parts (should be 3)"

if [ "$jwt_parts" -eq 3 ]; then
    echo "  ✅ JWT has correct structure"
    
    # Decode header and payload for verification
    header_decoded=$(echo "$jwt_token" | cut -d. -f1 | base64 -d 2>/dev/null)
    payload_decoded=$(echo "$jwt_token" | cut -d. -f2 | base64 -d 2>/dev/null)
    
    echo "  Header: $header_decoded"
    echo "  Payload: $payload_decoded"
    
    # Check if JSON is valid
    if echo "$header_decoded" | jq . >/dev/null 2>&1; then
        echo "  ✅ Header is valid JSON"
    else
        echo "  ❌ Header is not valid JSON"
    fi
    
    if echo "$payload_decoded" | jq . >/dev/null 2>&1; then
        echo "  ✅ Payload is valid JSON"
    else
        echo "  ❌ Payload is not valid JSON"
    fi
else
    echo "  ❌ JWT has incorrect structure"
fi

# Test token acquisition
echo ""
echo "Testing token acquisition..."
RESPONSE=$(curl -s -X POST \
  "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$TEST_CLIENT_ID" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$jwt_token" \
  -d "scope=api://$APP_ID/.default" \
  -d "grant_type=client_credentials")

echo "Token response: $RESPONSE"

# Check if we got a token
TOKEN=$(echo "$RESPONSE" | jq -r '.access_token // empty')
if [ ! -z "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    echo ""
    echo "✅ SUCCESS! Obtained access token"
    echo "Token: $TOKEN"
    
    # Decode and show token claims
    echo ""
    echo "Token claims:"
    echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "Could not decode token payload"
else
    echo ""
    echo "❌ FAILED to obtain token"
    ERROR=$(echo "$RESPONSE" | jq -r '.error_description // .error')
    echo "Error: $ERROR"
fi

# Clean up temporary files
rm -f test-cert.pem test-private.key