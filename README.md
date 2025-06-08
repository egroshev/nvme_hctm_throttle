# nvme_hctm_throttle repository
Nvme Host Controlled Thermal Management scripts repository. Initially created to limit the power consumption and performance of an 2230 2242 NVMe M.2 SSD in order to not exceed the 4.5W limit of the USB-C DockCase for NVMe SSDs to be used as USB devices.


# set_min_tmt.sh
USAGE:
  sudo ./set_min_tmt.sh [OPTIONS]
OPTIONS:
  --device, -d <path>     Specify the NVMe device (e.g., /dev/nvme1).
                          Defaults to /dev/nvme0.
  --change-both <bool>    Set to 'true' to change both TMT1 and TMT2, or 'false'
                          to change only TMT1. Defaults to 'false'.
EXAMPLES:
  # Change ONLY TMT1 on the default device (default behavior)
  sudo ./set_min_tmt.sh

  # Change BOTH TMT1 and TMT2 on the default device
  sudo ./set_min_tmt.sh --change-both true

  # Change BOTH TMT1 and TMT2 on a specific device
  sudo ./set_min_tmt.sh --device /dev/nvme1 --change-both TRUE


# nvme-cli command line input (manually setting without the need of set_min_tmt.sh)
EXAMPLE:
# --- Check if HCTM is supported (1), and minimum and maximum accepted TMT temperatures.
sudo nvme id-ctrl /dev/nvme0 -o json | jq -r '"\(.hctma) \(.mntmt) \(.mxtmt)"'
# --- Get Default TMT1 and TMT2 values ---
vals=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 1 -o json | jq .dw0) && echo "$((vals & 0xFFFF)) $(( (vals >> 16) & 0xFFFF))"
# --- Get Current TMT1 and TMT2 values ---
vals=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 0 -o json | jq .dw0) && echo "$((vals & 0xFFFF)) $(( (vals >> 16) & 0xFFFF))"
# -- Set your TMT1 and TMT2 values. Here I assume the reported mntmt was 273 Kelvin (0C) ---
sudo nvme set-feature /dev/nvme0 -f 0x10 -v $(( (273 << 16) | 275 ))
