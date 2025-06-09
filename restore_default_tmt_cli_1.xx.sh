#!/bin/bash

# ==============================================================================
# Restore Default SSD Thermal Management (TMT) Script (Legacy Compatible)
#
# Description:
# This script restores the Host Controlled Thermal Management (HCTM) values
# (TMT1 and TMT2) on an NVMe SSD back to their original factory defaults.
#
# It is designed to work with nvme-cli version 1.1 and newer by using
# standard text-parsing tools.
#
# USAGE:
#   sudo ./restore_defaults.sh [OPTIONS]
#
# OPTIONS:
#   --device, -d <path>     Specify the NVMe device (e.g., /dev/nvme1).
#                           Defaults to /dev/nvme0.
#   --save                  Makes the change persistent across reboots.
#
# EXAMPLE:
#   # Restore defaults on the primary NVMe drive
#   sudo ./restore_defaults.sh --save
#
#   # Restore defaults on a secondary NVMe drive
#   sudo ./restore_defaults.sh --device /dev/nvme1 --save
#
# REQUIREMENTS:
# 1. 'nvme-cli' version 1.1 or newer must be installed.
# 2. This script MUST be run with root privileges (e.g., using 'sudo').
# ==============================================================================

# --- Default Configuration ---
NVME_DEVICE="/dev/nvme0"
SAVE_FEATURE=false

# --- Script Input Processing ---
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--device)
        NVME_DEVICE="$2"
        shift # past argument
        shift # past value
        ;;
        --save)
        SAVE_FEATURE=true
        shift # past argument
        ;;
        *)    # unknown option
        echo "ERROR: Unknown option '$1'"
        echo "Usage: $0 [--device <path>] [--save]"
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
}

# Function to convert Kelvin to Celsius for display
kelvin_to_celsius() {
    echo $(($1 - 273))
}

# Run prerequisite checks
check_root
check_tools

echo "--- Restoring Default Thermal Management for: $NVME_DEVICE ---"
echo

# --- 1. Get and Print Default Thermal Values ---
HCTM_FEATURE_ID=0x10
get_tmt_values() {
    local selector=$1 # 0 for current, 1 for default
    # Get the raw text output, e.g., "get-feature:0x10 (...), Current value:0x01670115"
    local raw_output=$(nvme get-feature "$NVME_DEVICE" -f $HCTM_FEATURE_ID -s "$selector")
    # Extract the hex value after the last colon
    local hex_val=$(echo "$raw_output" | awk -F: '{print $NF}')
    # Convert hex to a decimal number the shell can use
    local feature_val=$((hex_val))

    # Correctly parse TMT1 (high word) and TMT2 (low word)
    local tmt1=$(((feature_val >> 16) & 0xFFFF))
    local tmt2=$((feature_val & 0xFFFF))

    echo "$tmt1 $tmt2"
}

echo "[STEP 1] Reading factory default TMT values..."
read -r DEFAULT_TMT1_K DEFAULT_TMT2_K < <(get_tmt_values 1)

if [ -z "$DEFAULT_TMT1_K" ] || [ -z "$DEFAULT_TMT2_K" ]; then
    echo "  [FAIL] Could not read default TMT values from the drive. Aborting."
    exit 1
fi

DEFAULT_TMT1_C=$(kelvin_to_celsius "$DEFAULT_TMT1_K")
DEFAULT_TMT2_C=$(kelvin_to_celsius "$DEFAULT_TMT2_K")
echo "  - Default TMT1 found: ${DEFAULT_TMT1_K}K / ${DEFAULT_TMT1_C}°C"
echo "  - Default TMT2 found: ${DEFAULT_TMT2_K}K / ${DEFAULT_TMT2_C}°C"
echo

# --- 2. Set New Values to Defaults ---
echo "[STEP 2] Applying factory default values..."

# Prepare the --save option flag if requested
save_opt=""
if [ "$SAVE_FEATURE" = true ]; then
    echo "  - Persistence: The values will be SAVED and will persist after a reboot."
    save_opt="--save"
else
    echo "  - Persistence: The values are TEMPORARY and will reset on reboot."
fi

# Correctly pack TMT1 into high bits and TMT2 into low bits
SET_VALUE=$(( (DEFAULT_TMT1_K << 16) | DEFAULT_TMT2_K ))
SET_VALUE_HEX=$(printf "0x%x" $SET_VALUE)
echo "  - Executing: nvme set-feature $NVME_DEVICE -f $HCTM_FEATURE_ID -v $SET_VALUE_HEX $save_opt"
nvme set-feature "$NVME_DEVICE" -f $HCTM_FEATURE_ID -v "$SET_VALUE" $save_opt
if [ $? -ne 0 ]; then
    echo "  [FAIL] Failed to set new TMT values. Aborting."
    exit 1
fi
echo "  - Default values have been set."
echo

# --- 3. Verify The Change ---
echo "[STEP 3] Verifying the change..."
read -r FINAL_TMT1_K FINAL_TMT2_K < <(get_tmt_values 0)
FINAL_TMT1_C=$(kelvin_to_celsius "$FINAL_TMT1_K")
FINAL_TMT2_C=$(kelvin_to_celsius "$FINAL_TMT2_K")

echo "  - Final Readout TMT1: ${FINAL_TMT1_K}K / ${FINAL_TMT1_C}°C"
echo "  - Final Readout TMT2: ${FINAL_TMT2_K}K / ${FINAL_TMT2_C}°C"

if [ "$FINAL_TMT1_K" -eq "$DEFAULT_TMT1_K" ] && [ "$FINAL_TMT2_K" -eq "$DEFAULT_TMT2_K" ]; then
    echo "  [SUCCESS] The values were restored to defaults successfully."
else
    echo "  [WARNING] Verification failed. The current values do not match the factory defaults."
fi
echo

echo "--- Script Finished ---"