#!/bin/bash

# Simple validation script for server.json using jq

set -e

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "✗ Error: jq is not installed. Please install jq to use this script."
    exit 1
fi

# Check if server.json exists
if [ ! -f "server.json" ]; then
    echo "✗ Error: server.json not found in current directory"
    exit 1
fi

# Validate JSON syntax
if ! jq empty server.json 2>/dev/null; then
    echo "✗ Error: server.json is not valid JSON"
    exit 1
fi

# Extract and validate required fields
NAME=$(jq -r '.name // empty' server.json)
VERSION=$(jq -r '.version // empty' server.json)
DESCRIPTION=$(jq -r '.description // empty' server.json)
PACKAGES=$(jq -r '.packages // empty' server.json)

ERRORS=()

# Check required fields
if [ -z "$NAME" ]; then
    ERRORS+=("Missing required field: name")
fi

if [ -z "$VERSION" ]; then
    ERRORS+=("Missing required field: version")
fi

if [ -z "$DESCRIPTION" ]; then
    ERRORS+=("Missing required field: description")
fi

if [ -z "$PACKAGES" ]; then
    ERRORS+=("Missing required field: packages")
fi

# Validate name format for GitHub namespace
if [[ "$NAME" == io.github.* ]]; then
    # Valid GitHub namespace
    :
elif [[ "$NAME" == .* ]]; then
    ERRORS+=("Name cannot start with a dot")
fi

# Count packages
PACKAGE_COUNT=$(jq '.packages | length' server.json)

# Check if there are validation errors
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "✗ Validation errors found:"
    for error in "${ERRORS[@]}"; do
        echo "  - $error"
    done
    exit 1
fi

# Success
echo "✓ server.json validation successful"
echo "  Name: $NAME"
echo "  Version: $VERSION"
echo "  Packages: $PACKAGE_COUNT"

# Optional: Check if schema is accessible
SCHEMA=$(jq -r '."$schema" // empty' server.json)
if [ -n "$SCHEMA" ]; then
    echo "  Schema: $SCHEMA"
    if command -v curl &> /dev/null; then
        if curl -s -f -o /dev/null "$SCHEMA"; then
            echo "  ✓ Schema URL is accessible"
        else
            echo "  ⚠ Warning: Schema URL is not accessible"
        fi
    fi
fi