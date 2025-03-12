#!/usr/bin/env bash
# main.sh
#
# Main script to manage ZFS pools and DigitalOcean volumes.
# This script orchestrates the entire workflow of:
# 1. Collecting system metadata
# 2. Scanning for new disks
# 3. Creating new volumes if needed
# 4. Creating or expanding ZFS pools
# 5. Testing performance
#
# Usage: ./main.sh [--poolname NAME]
#
# Options:
#   --poolname NAME : Specify a custom pool name (default: "tank")
#
# Requires:
#   - Root privileges
#   - DO_API_TOKEN environment variable (if creating new volumes)

set -e

# Colors and formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default pool name
POOL_NAME="tank"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --poolname)
      POOL_NAME="$2"
      shift 2
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      echo -e "Usage: $0 [--poolname NAME]"
      exit 1
      ;;
  esac
done

# Function to display progress bar
show_progress() {
  local pid=$1
  local message="$2"
  local delay=0.1
  local spinstr='|/-\'
  
  # Save cursor position
  tput sc
  
  while kill -0 $pid 2>/dev/null; do
    local temp=${spinstr#?}
    printf " %s [%c]  " "$message" "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    tput rc  # Restore cursor position
    tput el  # Clear to end of line
  done
  
  printf " %s [✓]  \n" "$message"
}

# Function to confirm actions
confirm() {
  local prompt=$1
  local default=${2:-Y}
  
  if [[ $default == "Y" ]]; then
    local options="[Y/n]"
  else
    local options="[y/N]"
  fi
  
  echo ""
  echo -e "${YELLOW}${prompt} ${options}${NC}"
  read -r response
  
  if [[ -z $response ]]; then
    response=$default
  fi
  
  if [[ $response =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root${NC}"
  exit 1
fi

# Display welcome message
echo ""
echo -e "${BOLD}${CYAN}🧙 ZFS Cloud Management Wizard${NC}"
echo -e "${BLUE}This script helps you manage ZFS pools on cloud block storage${NC}"
echo ""

# Step 1: Collect droplet metadata
echo -e "${BOLD}${BLUE}Step 1: Collecting system information...${NC}"
./terraform_get_droplet_metadata.sh > /tmp/droplet_metadata.json &
show_progress $! "Getting droplet metadata"

# Parse metadata
DROPLET_ID=$(jq -r '.droplet_id' /tmp/droplet_metadata.json)
REGION=$(jq -r '.region' /tmp/droplet_metadata.json)
HOSTNAME=$(jq -r '.hostname' /tmp/droplet_metadata.json)

echo -e "${BLUE}Droplet ID:${NC} ${BOLD}$DROPLET_ID${NC}"
echo -e "${BLUE}Region:${NC} ${BOLD}$REGION${NC}"
echo -e "${BLUE}Hostname:${NC} ${BOLD}$HOSTNAME${NC}"

# Step 2: Show current storage status
echo -e "\n${BOLD}${BLUE}Step 2: Checking current storage status...${NC}"
./summarize_storage.sh

# Step 3: Scan for new disks
echo -e "\n${BOLD}${BLUE}Step 3: Scanning for new disks...${NC}"
NEW_DISK=$(./find_new_disks.sh --largest 2>/dev/null || true)

if [ -z "$NEW_DISK" ]; then
  echo -e "${YELLOW}No new unformatted disks found.${NC}"
  
  if confirm "Would you like to create a new DigitalOcean volume?"; then
    # Ask for volume name
    echo -e "${BLUE}Enter a name for the new volume (default: ${BOLD}$POOL_NAME${NC}${BLUE}):${NC}"
    read -r VOLUME_NAME
    
    if [ -z "$VOLUME_NAME" ]; then
      VOLUME_NAME="$POOL_NAME"
    fi
    
    # Ask for volume size
    echo -e "${BLUE}Enter size in GB for the new volume (default: ${BOLD}100${NC}${BLUE}):${NC}"
    read -r VOLUME_SIZE
    
    if [ -z "$VOLUME_SIZE" ]; then
      VOLUME_SIZE="100"
    fi
    
    # Create new volume
    echo -e "\n${BOLD}${BLUE}Creating new DigitalOcean volume...${NC}"
    NEW_DISK=$(./terraform_create_new_volume.sh "$VOLUME_NAME" "$REGION" "$DROPLET_ID" "$VOLUME_SIZE") &
    show_progress $! "Creating and attaching volume"
    
    echo -e "${GREEN}New disk created: ${BOLD}$NEW_DISK${NC}"
  else
    echo -e "${RED}No disk available. Exiting.${NC}"
    exit 0
  fi
else
  echo -e "${GREEN}Found new disk: ${BOLD}$NEW_DISK${NC}"
fi

# Step 4: Check for existing ZFS pools
echo -e "\n${BOLD}${BLUE}Step 4: Checking for existing ZFS pools...${NC}"
EXISTING_POOLS=$(zpool list -H -o name 2>/dev/null || echo "")

if [ -n "$EXISTING_POOLS" ]; then
  echo -e "${GREEN}Found existing ZFS pools:${NC}"
  zpool list
  
  echo -e "\n${BLUE}You have three options for the new disk:${NC}"
  echo -e "  ${BOLD}1)${NC} Add as stripe to an existing pool (increases capacity)"
  echo -e "  ${BOLD}2)${NC} Add as mirror to an existing pool (increases redundancy)"
  echo -e "  ${BOLD}3)${NC} Create a new pool"
  
  echo -e "\n${BLUE}Select an option [1-3]:${NC}"
  read -r OPTION
  
  case $OPTION in
    1)
      # Add as stripe
      if [ "$(echo "$EXISTING_POOLS" | wc -l)" -gt 1 ]; then
        echo -e "${BLUE}Which pool do you want to add the disk to?${NC}"
        select POOL_NAME in $EXISTING_POOLS; do
          if [ -n "$POOL_NAME" ]; then
            break
          fi
        done
      else
        POOL_NAME="$EXISTING_POOLS"
      fi
      
      if confirm "Add disk $NEW_DISK as a stripe to pool $POOL_NAME?"; then
        echo -e "\n${BOLD}${BLUE}Adding disk as a stripe...${NC}"
        ./zfs_add_stripe.sh "$POOL_NAME" "$NEW_DISK" &
        show_progress $! "Adding disk as stripe to $POOL_NAME"
      fi
      ;;
      
    2)
      # Add as mirror
      if [ "$(echo "$EXISTING_POOLS" | wc -l)" -gt 1 ]; then
        echo -e "${BLUE}Which pool do you want to add the disk to?${NC}"
        select POOL_NAME in $EXISTING_POOLS; do
          if [ -n "$POOL_NAME" ]; then
            break
          fi
        done
      else
        POOL_NAME="$EXISTING_POOLS"
      fi
      
      # Check if a specific device should be mirrored
      echo -e "${BLUE}Do you want to specify which device to mirror? (default: auto-detect)${NC}"
      read -r MIRROR_DEVICE
      
      if [ -z "$MIRROR_DEVICE" ]; then
        if confirm "Add disk $NEW_DISK as a mirror to pool $POOL_NAME (auto-detect mirror target)?"; then
          echo -e "\n${BOLD}${BLUE}Adding disk as a mirror...${NC}"
          ./zfs_add_mirror.sh "$POOL_NAME" "$NEW_DISK" &
          show_progress $! "Adding disk as mirror to $POOL_NAME"
        fi
      else
        if confirm "Add disk $NEW_DISK as a mirror to device $MIRROR_DEVICE in pool $POOL_NAME?"; then
          echo -e "\n${BOLD}${BLUE}Adding disk as a mirror...${NC}"
          ./zfs_add_mirror.sh "$POOL_NAME" "$NEW_DISK" "$MIRROR_DEVICE" &
          show_progress $! "Adding disk as mirror to $POOL_NAME"
        fi
      fi
      ;;
      
    3)
      # Create a new pool
      echo -e "${BLUE}Enter a name for the new pool (default: ${BOLD}$POOL_NAME${NC}${BLUE}):${NC}"
      read -r NEW_POOL_NAME
      
      if [ -n "$NEW_POOL_NAME" ]; then
        POOL_NAME="$NEW_POOL_NAME"
      fi
      
      if confirm "Create a new pool named $POOL_NAME using disk $NEW_DISK?"; then
        echo -e "\n${BOLD}${BLUE}Creating new ZFS pool...${NC}"
        ./zfs_create_pool.sh "$POOL_NAME" "$NEW_DISK" &
        show_progress $! "Creating new pool $POOL_NAME"
      fi
      ;;
      
    *)
      echo -e "${RED}Invalid option. Exiting.${NC}"
      exit 1
      ;;
  esac
else
  # No existing pools, create a new one
  echo -e "${YELLOW}No existing ZFS pools found.${NC}"
  
  echo -e "${BLUE}Enter a name for the new pool (default: ${BOLD}$POOL_NAME${NC}${BLUE}):${NC}"
  read -r NEW_POOL_NAME
  
  if [ -n "$NEW_POOL_NAME" ]; then
    POOL_NAME="$NEW_POOL_NAME"
  fi
  
  if confirm "Create a new pool named $POOL_NAME using disk $NEW_DISK?"; then
    echo -e "\n${BOLD}${BLUE}Creating new ZFS pool...${NC}"
    ./zfs_create_pool.sh "$POOL_NAME" "$NEW_DISK" &
    show_progress $! "Creating new pool $POOL_NAME"
  else
    echo -e "${RED}Operation cancelled. Exiting.${NC}"
    exit 0
  fi
fi

# Step 5: Show final storage status
echo -e "\n${BOLD}${BLUE}Step 5: Displaying updated storage status...${NC}"
./summarize_storage.sh

# Step 6: Run speed test
if confirm "Would you like to run a speed test on the ZFS pool?"; then
  echo -e "\n${BOLD}${BLUE}Step 6: Running speed test...${NC}"
  ./speedtest.sh "$POOL_NAME"
fi

# Step 7: Show ZFS usage examples
echo -e "\n${BOLD}${BLUE}ZFS Usage Examples:${NC}"
echo -e "${YELLOW}Create a new dataset:${NC}"
echo -e "  zfs create $POOL_NAME/mynewdataset"
echo -e "${YELLOW}Set compression options:${NC}"
echo -e "  zfs set compression=zstd $POOL_NAME/mynewdataset"
echo -e "${YELLOW}Check used space:${NC}"
echo -e "  zfs list $POOL_NAME"
echo -e "${YELLOW}Create a snapshot:${NC}"
echo -e "  zfs snapshot -r $POOL_NAME@backup-$(date +%Y%m%d)"
echo -e "${YELLOW}View all snapshots:${NC}"
echo -e "  zfs list -t snapshot"

echo -e "\n${BOLD}${GREEN}ZFS Cloud Management Wizard completed successfully!${NC}"
