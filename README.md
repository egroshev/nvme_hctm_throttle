# nvme_hctm_throttle repository
Nvme Host Controlled Thermal Management scripts repository. Initially created to limit the power consumption and performance of an 2230 2242 NVMe M.2 SSD in order to not exceed the 4.5W limit of the USB-C DockCase for NVMe SSDs to be used as USB devices.

The way this works is the script sets TMT1 and/or TMT2 to it's minimum allowed value, which is usually at or below 0C, to force it to throttle at all points above that minimum temp. Your SSD usually always opperates at above 0C, thus allowing permanent throttling to take place.


# set_min_tmt.sh
### USAGE:
    chmod +x ./set_min_tmt.sh
    sudo ./set_min_tmt.sh [OPTIONS]
### OPTIONS:
    --device, -d <path>     Specify the NVMe device (e.g., /dev/nvme1).
                            Defaults to /dev/nvme1.
    --change-both <bool>    Set to 'true' to change both TMT1 and TMT2, or 'false'
                            to change only TMT1. Defaults to 'false'.
    --save                  Makes the settings change persistent across reboots.
### EXAMPLES:
  #### Change ONLY TMT1 on the default device but don't save across power cycles (default behavior)
    sudo ./set_min_tmt.sh

  #### Change BOTH TMT1 and TMT2 on the default device and save
    sudo ./set_min_tmt.sh --change-both true --save

  #### Change BOTH TMT1 and TMT2 on a specific device and save
    sudo ./set_min_tmt.sh --device /dev/nvme2 --change-both TRUE --save


# Extra: Manually performing CLI entry (without script)
### EXAMPLE (nvme-cli 2.1+):
  #### Identify your NVMe SSD device (match it to the MN Model number on your SSD sticker).
    sudo nvme list
  #### Check if HCTM is supported (1), and minimum and maximum accepted TMT temperatures.
    sudo nvme id-ctrl /dev/nvme0 -o json | jq -r '"\(.hctma) \(.mntmt) \(.mxtmt)"'
  #### Get Default TMT1 and TMT2 values
    vals=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 1 -o json | jq .dw0) && echo "$((vals & 0xFFFF)) $(( (vals >> 16) & 0xFFFF)) Kelvin^"
  #### Get Current TMT1 and TMT2 values
    vals=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 0 -o json | jq .dw0) && echo "$((vals & 0xFFFF)) $(( (vals >> 16) & 0xFFFF)) Kelvin^"
  #### Set your TMT1 and TMT2 values. Here I assume the reported mntmt was 273 Kelvin (0C)
    sudo nvme set-feature /dev/nvme0 -f 0x10 -v $(( (273 << 16) | 275 )) --save
### EXAMPLE (nvme-cli 1.1+):
  #### Identify your NVMe SSD device (match it to the MN Model number on your SSD sticker).
    sudo nvme list
  #### Check if HCTM is supported (1), and minimum and maximum accepted TMT temperatures.
    sudo nvme id-ctrl /dev/nvme0 | grep -E '^hctma|^mntmt|^mxtmt' | awk '{print $3}' | xargs
  #### Get Default TMT1 and TMT2 values
    hexval=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 1 | awk -F: '{print $NF}'); vals=$((hexval)); echo "$(((vals >> 16) & 0xFFFF)) $((vals & 0xFFFF)) Kelvin^"
  #### Get Current TMT1 and TMT2 values
    hexval=$(sudo nvme get-feature /dev/nvme0 -f 0x10 -s 0 | awk -F: '{print $NF}'); vals=$((hexval)); echo "$(((vals >> 16) & 0xFFFF)) $((vals & 0xFFFF)) Kelvin^"
  #### Set your TMT1 and TMT2 values. Here I assume the reported mntmt was 273 Kelvin (0C)
    sudo nvme set-feature /dev/nvme0 -f 0x10 -v $(( (273 << 16) | 275 )) --save
  #### Note that all values from SSD are reported in Kelvin. Make sure to keep it in Kelvin!!! But if you're curious about your SSD's limits you can convert it to human readable format by seeing what it is in celcius.
      Note: Celcius = X - 273 Kelvin
