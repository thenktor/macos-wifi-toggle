#!/bin/bash

# Automatically toggle macOS Wi-Fi based on ethernet status (uses launchd).
# If ethernet is active, Wi-Fi is disabled. If ethernet is inactive, Wi-Fi is enabled.

PATH="/bin:/sbin:/usr/bin:/usr/sbin"
LAUNCHD_SERVICE_NAME="nz.haume.wifi-toggle"
LAUNCHD_SERVICE_FILE="${HOME}/Library/LaunchAgents/${LAUNCHD_SERVICE_NAME}.plist"
DEBUG="yes"

# Each regex must match a single interface from `networksetup -listnetworkserviceorder`
# eg. "(2) CalDigit TS3" or "(1) Apple USB Ethernet Adapter"
ETHERNET_REGEX=".*_wifi-toggle"
# ETHERNET_REGEX="Apple USB Ethernet Adapter"
# ETHERNET_REGEX="Ethernet"
WIFI_REGEX="(Wi-Fi|Airport)"

print_usage() {
  echo -e "Automatically toggle macOS Wi-Fi based on ethernet status (uses launchd)\n"
  echo "Usage: $(basename $0) [ on | off | help ]"
  echo "   on - start automatically toggling Wi-Fi (install launchd service)"
  echo "  off - stop automatically toggling Wi-Fi (uninstall launchd service)"
  echo "  run - Toggle Wi-Fi status (run by launchd)"
  exit 1
}

print_error() {
  echo -e "ERROR: $1" >&2
  exit 1
}

print_debug() {
  test -n "$DEBUG" && echo -e "DEBUG: $1" >&2
}

notify() {
  # Configure notifications in: System Settings > Notifications > Script Editor
  osascript -e "display notification \"by $(basename $0)\" with title \"$1\""
}

is_launchd_enabled() {
  if launchctl print gui/$(id -u)/nz.haume.wifi-toggle > /dev/null 2>&1; then
    print_debug "is_launchd_loaded(): $LAUNCHD_SERVICE_NAME already loaded"
    return 0
  else
    print_debug "is_launchd_loaded(): $LAUNCHD_SERVICE_NAME not loaded"
    return 1
  fi
}

enable_launchd() {
  echo "Creating launchd service: $LAUNCHD_SERVICE_FILE"
  cat <<EOF > "$LAUNCHD_SERVICE_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_SERVICE_NAME}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>ProgramArguments</key>
  <array>
  <string>$(realpath "$0")</string>
  <string>run</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Preferences/SystemConfiguration</string>
  </array>
</dict>
</plist>
EOF
  echo "Enabling launchd service: $LAUNCHD_SERVICE_NAME"
  launchctl bootstrap gui/$(id -u) "$LAUNCHD_SERVICE_FILE"
}

disable_launchd() {
  echo "Disabling launchd service: $LAUNCHD_SERVICE_NAME"
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/nz.haume.wifi-toggle.plist
  rm "$LAUNCHD_SERVICE_FILE"
}

get_interfaces() {
  test -z "$1" && print_error "get_interfaces(): no regex provided"
  INTERFACE=$(networksetup -listnetworkserviceorder | grep -E -A 1 "^\([0-9]+\).* $1" | grep -E -o "en[0-9]+")

  if [ -z "$INTERFACE" ]; then
    print_error "No ethernet interface matches: $1"
  fi

  INTERFACE=$(printf '%s' "$INTERFACE" | tr '\n' ' ')
  print_debug "get_interfaces(): regex '$1' -> interface '$INTERFACE'"
  echo "$INTERFACE"
}

is_interface_active() {
  test -z "$1" && print_error "is_interface_active(): no interface provided"

  if ifconfig "$1" 2>&1 | grep -q "status: active"; then
    echo -n "active"
    return 0
  else
    echo -n "inactive"
    return 1
  fi
}

toggle_wifi() {
  ETHERNET_INTERFACES=$(get_interfaces "$ETHERNET_REGEX")
  WIFI_INTERFACE=$(get_interfaces "$WIFI_REGEX")

  WIFI_STATUS=$(is_interface_active "$WIFI_INTERFACE")

  if [ "$WIFI_STATUS" == "active" ]; then
    for ETH in $ETHERNET_INTERFACES; do
      ETHERNET_STATUS=$(is_interface_active "$ETH")
      print_debug "ethernet status $ETH: '$ETHERNET_STATUS', wifi status: '$WIFI_STATUS'"
      if [ "$ETHERNET_STATUS" == "active" ]; then
        print_debug "disabling wifi"
        networksetup -setairportpower "$WIFI_INTERFACE" off
        notify "Wi-Fi Disabled"
        break
      else
        print_debug "not toggling wifi status"
      fi
    done
  elif [ "$WIFI_STATUS" == "inactive" ]; then
    for ETH in $ETHERNET_INTERFACES; do
      ETHERNET_STATUS=$(is_interface_active "$ETH")
      print_debug "ethernet status $ETH: '$ETHERNET_STATUS', wifi status: '$WIFI_STATUS'"
      if [ "$ETHERNET_STATUS" == "active" ]; then
        break
      fi
    done
    if [ "$ETHERNET_STATUS" == "inactive" ]; then
      print_debug "enabling wifi"
      networksetup -setairportpower "$WIFI_INTERFACE" on
      notify "Wi-Fi Enabled"
    else
      print_debug "not toggling wifi status"
    fi
  else
    print_error "unknown wifi status"
  fi
}

### main script
if [ "${OSTYPE:0:6}" != "darwin" ]; then
  print_error "This script only runs on macOS"
fi

if [ "$1" == "run" ]; then
  toggle_wifi

elif [ "$1" == "on" ]; then
  LAUNCHDIR="${HOME}/Library/LaunchAgents"
  if [ -d "${LAUNCHDIR}" ]; then
    print_debug "${LAUNCHDIR} exists"
  else
    print_debug "${LAUNCHDIR} does not exist"
    mkdir "${HOME}/Library/LaunchAgents" && echo "Created directory ${HOME}/Library/LaunchAgents"
  fi
  
  if is_launchd_enabled; then
    print_error "launchd service already enabled"
  else
    enable_launchd
  fi

elif [ "$1" == "off" ]; then
  if is_launchd_enabled; then
    disable_launchd
  else
    print_error "launchd service already disabled"
  fi

else
  print_usage

fi
