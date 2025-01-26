#!/bin/bash

# Script to update Yosys and Icarus Verilog versions in README.md

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display error messages
error() {
    echo "Error: $1" >&2
    exit 1
}

# Function to update a version in README.md
# Arguments:
#   $1 - Tool name (e.g., "Yosys")
#   $2 - Command to get version (e.g., "yosys -V")
#   $3 - Path to README.md
update_version() {
    local tool_name="$1"
    local version_command="$2"
    local readme_file="$3"

    echo "Updating version for $tool_name..."

    # Check if the command exists
    local cmd
    cmd=$(echo "$version_command" | awk '{print $1}')
    if ! command -v "$cmd" &> /dev/null; then
        error "$tool_name is not installed or not in the PATH."
    fi

    # Get the version output
    version_output=$($version_command)

    # Debug: Show the version output
    echo "Version output for $tool_name:"
    echo "$version_output"

    # Extract the version number using regex
    local version=""
    if [[ "$tool_name" == "Yosys" ]]; then
        if [[ "$version_output" =~ Yosys[[:space:]]([0-9]+\.[0-9]+) ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    elif [[ "$tool_name" == "Icarus Verilog" ]]; then
        if [[ "$version_output" =~ Icarus[[:space:]]Verilog[[:space:]]version[[:space:]]([0-9]+\.[0-9]+) ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    else
        # Generic regex: ToolName followed by version number
        if [[ "$version_output" =~ $tool_name[[:space:]]([0-9]+\.[0-9]+) ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    fi

    if [[ -z "$version" ]]; then
        error "Failed to parse $tool_name version from output."
    fi

    echo "Detected $tool_name version: $version"

    # Check if README.md exists
    if [[ ! -f "$readme_file" ]]; then
        error "$readme_file not found."
    fi

    # Create a backup of README.md if not already created
    local backup_file="${readme_file}.bak"
    if [[ ! -f "$backup_file" ]]; then
        cp "$readme_file" "$backup_file"
        echo "Backup of $readme_file created at $backup_file"
    fi

    # Prepare the sed search and replacement patterns
    # We'll match the tool name and its version number, regardless of the URL
    # This avoids dealing with slashes in URLs
    # Example line: - [Yosys 0.48](https://github.com/YosysHQ/yosys)
    # We'll capture and replace only the version number

    # Escape any special characters in tool_name for regex
    local escaped_tool_name
    escaped_tool_name=$(printf '%s\n' "$tool_name" | sed 's/[]\/$*.^|[]/\\&/g')

    # Define the regex pattern to match the tool name and version
    local regex_pattern="\[${escaped_tool_name} [0-9]+\.[0-9]+\]"

    # Define the replacement string with the new version
    local replacement="[$tool_name $version]"

    # Debug: Show the regex pattern and replacement
    echo "Regex pattern: $regex_pattern"
    echo "Replacement: $replacement"

    # Use sed to replace the version number
    # We'll use | as the delimiter to avoid conflicts with /
    # This command searches for "[ToolName X.XX]" and replaces it with "[ToolName NEW_VERSION]"
    sed -E -i.bak "s|${regex_pattern}|${replacement}|g" "$readme_file"

    # Check if sed made any changes
    if grep -q "\[$tool_name $version\]" "$readme_file"; then
        echo "$tool_name version in $readme_file has been updated to $version."
    else
        echo "Warning: $tool_name version in $readme_file was not updated. Please check the file manually."
    fi
}

# Define the path to README.md
# Modify this if your README.md is in a different location
readme_path="./docs/README.md"

# Update Yosys version
update_version "Yosys" "yosys -V" "$readme_path"

# Update Icarus Verilog version
update_version "Icarus Verilog" "iverilog -V" "$readme_path"

# Optional: Remove the temporary sed backups if desired
# Uncomment the following lines to remove sed backup files
# find . -type f -name "*.bak" ! -name "*.backup" -exec rm {} \;
# echo "Temporary sed backup files removed."

echo "All versions have been updated successfully."
