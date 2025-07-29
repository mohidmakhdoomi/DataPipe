#!/bin/bash

# Script to enable/disable clear-thought in .kiro/settings/mcp.json
# Usage: ./script.sh [true|false]
#   true  - disable the server
#   false - enable the server

PATH="/c/Program Files/Git/usr/bin:$PATH"

CONFIG_FILE=".kiro/settings/mcp.json"

# Check if argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 [true|false]"
    echo "  true  - disable clear-thought"
    echo "  false - enable clear-thought"
    exit 1
fi

# Validate the argument
DISABLED_VALUE="$1"
if [ "$DISABLED_VALUE" != "true" ] && [ "$DISABLED_VALUE" != "false" ]; then
    echo "Error: Argument must be 'true' or 'false'"
    echo "Usage: $0 [true|false]"
    exit 1
fi


# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found!"
    exit 1
fi

# Check if jq is available for JSON manipulation
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    echo "On Ubuntu/Debian: sudo apt-get install jq"
    echo "On macOS: brew install jq"
    exit 1
fi

# # Create a backup of the original file
# cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
# echo "Created backup: $CONFIG_FILE.backup"

# Use jq to modify the JSON and set disabled to false for clear-thought
jq --argjson disabled "$DISABLED_VALUE" '.mcpServers["clear-thought"].disabled = $disabled' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"

# Check if jq command was successful
if [ $? -eq 0 ]; then
    # Replace the original file with the modified version
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    
    echo "Successfully set disabled=$DISABLED_VALUE for clear-thought in $CONFIG_FILE"
    
    # Display the updated configuration for verification
    echo ""
    echo "Updated clear-thought configuration:"
    jq '.mcpServers["clear-thought"]' "$CONFIG_FILE"
else
    echo "Error: Failed to modify JSON file"
    rm -f "$CONFIG_FILE.tmp"
    exit 1
fi