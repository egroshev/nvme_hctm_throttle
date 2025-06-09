#!/bin/bash

# ==============================================================================
# Advanced SSD Thermal Management (TMT) Script
#
# Description:
# This script performs a sequence of operations using newer version of 'nvme-cli':
# 1. Checks if Host Controlled Thermal Management (HCTM) is supported.
# 2. Reads the drive's min/max supported temperature thresholds.
# 3. Reads the default and current TMT1 and TMT2 values.
# 4. Sets TMT1 to the drive's minimum allowed value (MNTMT).
# 5. Optionally sets TMT2 to MNTMT + 2 Kelvin, if specified via arguments.
# 6. Verifies that the new settings have been applied.
#
# USAGE:
#   sudo ./set_min_tmt.sh [OPTIONS]
#
# OPTIONS:
#   --device, -d <path>     Specify the NVMe device (e.g., /dev/nvme1).
#                           Defaults to /dev/nvme0.
#   --change-both <bool>    Set to 'true' to change both TMT1 and TMT2, or 'false'
#                           to change only TMT1. Defaults to 'false'.
#
# EXAMPLES:
#   # Change ONLY TMT1 on the default device (default behavior)
#   sudo ./set_min_tmt.sh
#
#   # Change BOTH TMT1 and TMT2 on the default device
#   sudo ./set_min_tmt.sh --change-both true
#
#   # Change BOTH TMT1 and TMT2 on a specific device
#   sudo ./set_min_tmt.sh --device /dev/nvme1 --change-both TRUE
#
# REQUIREMENTS:
# 1. 'nvme-cli' version 2.1 or greater must be installed. (e.g., sudo apt-get install nvme-cli).
# 2. jq must be installed for JSON parsing (e.g., sudo apt-get install jq).
# 3. This script MUST be run with root privileges (e.g., using 'sudo').
#
# WARNING:
# NVMe Host Controlled Thermal Management operations are PERSISTENT across
# power cycles. If you make these changes, your SSD will not revert back to
# default on its own and your SSDs performance will be in a throttled state
# unless this procedure is explicitely run again to restore the TMT values.
# Modifying your SSD's thermal management settings is an advanced operation.
#
# Manually Running nvme-cli Commands
# --- Check if HCTM is supported (1), and  minimum and maiximum accepted TMT temperature.
# sudo nvme id-ctrl /dev/nvme0 -o json | jq -r '"\(.hctma) \(.mntmt) \(.mxtmt)"'
# --- Get Default TMT1 and TMT2 values ---
# vals=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 1 -o json | jq .dw0) && echo "$((vals & 0xFFFF)) $(( (vals >> 16) & 0xFFFF))"
# --- Get Current TMT1 and TMT2 values ---
# vals=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 0 -o json | jq .dw0) && echo "$((vals & 0xFFFF)) $(( (vals >> 16) & 0xFFFF))"
# -- Set your TMT1 and TMT2 values. Here I assume the reported mntmt was 273 Kelvin ---
# sudo nvme set-feature /dev/nvme0 -f 0x10 -v $(( (273 << 16) | 275 ))
# ==============================================================================

# --- Default Configuration ---
NVME_DEVICE="/dev/nvme0"
CHANGE_BOTH=false

# --- Script Input Processing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--device)
        NVME_DEVICE="$2"
        shift # past argument
        shift # past value
        ;;
        --change-both|-change-both)
        if [ -z "$2" ]; then
            echo "ERROR: Option '$1' requires a value (true/false)."
            exit 1
        fi
        val=$(echo "$2" | tr '[:upper:]' '[:lower:]')
        if [[ "$val" == "true" ]]; then
            CHANGE_BOTH=true
        elif [[ "$val" == "false" ]]; then
            CHANGE_BOTH=false
        else
            echo "ERROR: Invalid value for '$1'. Expected 'true' or 'false', but got '$2'."
            exit 1
        fi
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option
        echo "ERROR: Unknown option '$1'"
        echo "Usage: $0 [--device <path>] [--change-both <true|false>]"
        exit 1
        ;;
    esac
done


# --- Script Body ---

# Function to check for root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "ERROR: Please run this script as root or with sudo."
        exit 1
    fi
}

# Function to check for required tools
check_tools() {
    if ! command -v nvme &> /dev/null; then
        echo "ERROR: 'nvme-cli' is not installed. Please install it to continue."
        exit 1
    fi
    if ! command -v jq &> /dev/null;        then
        echo "ERROR: 'jq' is not installed. Please install it to continue (e.g., sudo apt install jq)."
        exit 1
    fi

    # Check nvme-cli version
    local version_string=$(nvme --version | awk '/version/{print $3}')
    if [ -z "$version_string" ]; then
        echo "WARNING: Could not determine nvme-cli version. Assuming it is sufficient."
        return
    fi
    local major=$(echo "$version_string" | cut -d'.' -f1)
    local minor=$(echo "$version_string" | cut -d'.' -f2)

    # We need version > 2.0 (i.e., 2.1 or newer) for JSON support
    if (( major < 2 )) || (( major == 2 && minor <= 0 )); then
        echo "ERROR: nvme-cli version must be greater than 2.1 for this script."
        echo "       Your version is: $version_string"
        exit 1
    fi
}

# Function to convert Kelvin to Celsius for display
kelvin_to_celsius() {
    echo $(($1 - 273))
}

# Run prerequisite checks
check_root
check_tools

echo "--- Starting Advanced Thermal Management for: $NVME_DEVICE ---"
echo "--- Mode: Change Both TMT1 & TMT2 = $CHANGE_BOTH"
echo

# --- 1. Check Controller Capabilities ---
echo "[STEP 1] Checking Controller Capabilities..."
ID_CTRL_JSON=$(nvme id-ctrl "$NVME_DEVICE" -o json)
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to read controller data from $NVME_DEVICE. Aborting."
    exit 1
fi

# 1a. Check if HCTM is supported
HCTMA_SUPPORTED=$(echo "$ID_CTRL_JSON" | jq .hctma)
if [ "$HCTMA_SUPPORTED" -eq 1 ]; then
    echo "  [OK] Host Controlled Thermal Management (HCTMA) is supported."
else
    echo "  [FAIL] Host Controlled Thermal Management (HCTMA) is NOT supported. Aborting."
    exit 1
fi
echo

# 1b. Get and print Minimum and Maximum TMT values
echo "[STEP 2] Checking Temperature Threshold Range..."
MNTMT_K=$(echo "$ID_CTRL_JSON" | jq .mntmt)
MXTMT_K=$(echo "$ID_CTRL_JSON" | jq .mxtmt)
MNTMT_C=$(kelvin_to_celsius "$MNTMT_K")
MXTMT_C=$(kelvin_to_celsius "$MXTMT_K")
echo "  - Minimum Settable Threshold (MNTMT): ${MNTMT_K}K or ${MNTMT_C}°C"
echo "  - Maximum Settable Threshold (MXTMT): ${MXTMT_K}K or ${MXTMT_C}°C"
echo

if [ "$MNTMT_K" -eq 0 ] || [ "$MXTMT_K" -eq 0 ]; then
    echo "WARNING: Drive reports a min or max threshold of 0K. This may indicate the feature is not fully supported despite the HCTMA flag."
fi

# --- 2. Get and Print Thermal Values ---
HCTM_FEATURE_ID=0x10
get_tmt_values() {
    local selector=$1 # 0 for current, 1 for default
    local feature_val=$(nvme get-feature "$NVME_DEVICE" -f $HCTM_FEATURE_ID -s "$selector" -o json | jq .dw0)
    # local tmt1=$((feature_val & 0xFFFF))
    # local tmt2=$(((feature_val >> 16) & 0xFFFF))
    local tmt2_k=$((feature_val & 0xFFFF))
    local tmt1_k=$(((feature_val >> 16) & 0xFFFF))
    echo "$tmt1 $tmt2"
}

echo "[STEP 3] Reading Thermal Management Thresholds (TMT)..."
read -r DEFAULT_TMT1_K DEFAULT_TMT2_K < <(get_tmt_values 1)
DEFAULT_TMT1_C=$(kelvin_to_celsius "$DEFAULT_TMT1_K")
DEFAULT_TMT2_C=$(kelvin_to_celsius "$DEFAULT_TMT2_K")
echo "  - Default TMT1: ${DEFAULT_TMT1_K}K or ${DEFAULT_TMT1_C}°C"
echo "  - Default TMT2: ${DEFAULT_TMT2_K}K or ${DEFAULT_TMT2_C}°C"

read -r CURRENT_TMT1_K CURRENT_TMT2_K < <(get_tmt_values 0)
CURRENT_TMT1_C=$(kelvin_to_celsius "$CURRENT_TMT1_K")
CURRENT_TMT2_C=$(kelvin_to_celsius "$CURRENT_TMT2_K")
echo "  - Current TMT1: ${CURRENT_TMT1_K}K or ${CURRENT_TMT1_C}°C"
echo "  - Current TMT2: ${CURRENT_TMT2_K}K or ${CURRENT_TMT2_C}°C"
echo

# --- 3. Set New Values ---
echo "[STEP 4] Calculating and setting new TMT values..."
NEW_TMT1_K=$MNTMT_K # TMT1 is always set to the minimum.

if [ "$CHANGE_BOTH" = true ]; then
    echo "  - Both TMT1 and TMT2 will be changed."
    NEW_TMT2_K=$((MNTMT_K + 2))
else
    echo "  - Only TMT1 will be changed. TMT2 will be kept at its current value."
    NEW_TMT2_K=$CURRENT_TMT2_K
fi

NEW_TMT1_C=$(kelvin_to_celsius "$NEW_TMT1_K")
NEW_TMT2_C=$(kelvin_to_celsius "$NEW_TMT2_K")
echo "  - New Target TMT1: ${NEW_TMT1_K}K or ${NEW_TMT1_C}°C"
echo "  - New Target TMT2: ${NEW_TMT2_K}K or ${NEW_TMT2_C}°C"

if [ "$NEW_TMT2_K" -gt "$MXTMT_K" ]; then
    echo "  [FAIL] Calculated TMT2 (${NEW_TMT2_K}K) exceeds drive's maximum (${MXTMT_K}K). Aborting."
    exit 1
fi
echo "  [OK] New values are within the drive's supported range."

#SET_VALUE=$(( (NEW_TMT2_K << 16) | NEW_TMT1_K ))
SET_VALUE=$(( (NEW_TMT1_K << 16) | NEW_TMT2_K ))
SET_VALUE_HEX=$(printf "0x%x" $SET_VALUE)
echo "  - Executing: nvme set-feature $NVME_DEVICE -f $HCTM_FEATURE_ID -v $SET_VALUE_HEX"
nvme set-feature "$NVME_DEVICE" -f $HCTM_FEATURE_ID -v "$SET_VALUE"
if [ $? -ne 0 ]; then
    echo "  [FAIL] Failed to set new TMT values. Aborting."
    exit 1
fi
echo "  - New values have been set."
echo

# --- 4. Verify The Change ---
echo "[STEP 5] Verifying the change..."
read -r FINAL_TMT1_K FINAL_TMT2_K < <(get_tmt_values 0)
FINAL_TMT1_C=$(kelvin_to_celsius "$FINAL_TMT1_K")
FINAL_TMT2_C=$(kelvin_to_celsius "$FINAL_TMT2_K")

echo "  - Final Readout TMT1: ${FINAL_TMT1_K}K or ${FINAL_TMT1_C}°C"
echo "  - Final Readout TMT2: ${FINAL_TMT2_K}K or ${FINAL_TMT2_C}°C"

if [ "$FINAL_TMT1_K" -eq "$NEW_TMT1_K" ] && [ "$FINAL_TMT2_K" -eq "$NEW_TMT2_K" ]; then
    echo "  [SUCCESS] The values were updated successfully."
else
    echo "  [WARNING] Verification failed. The final values do not match the target values."
fi
echo

echo "--- Script Finished ---"