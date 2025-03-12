# ZFS Cloud Management Toolkit

This toolkit provides a collection of modular scripts to manage ZFS pools with DigitalOcean block storage volumes. The scripts are designed to be simple, modular, and reusable.

## Overview

The toolkit consists of:

1. A main script that orchestrates the entire workflow
2. Individual micro-scripts that each handle a specific task
3. A setup script to make sure everything is ready to run

## Getting Started

### Prerequisites

- A DigitalOcean droplet
- Root access
- DigitalOcean API token with read/write permissions (to create new volumes)

### Installation

1. Clone or download this repository to your DigitalOcean droplet
2. Run the setup script to make all component scripts executable and check for required dependencies:

```bash
sudo ./setup.sh
```

3. Set your DigitalOcean API token if you plan to create new volumes:

```bash
export DO_API_TOKEN=your_token_here
```

### Running the Toolkit

Execute the main script:

```bash
sudo ./main.sh
```

Optionally, you can specify a custom pool name:

```bash
sudo ./main.sh --poolname mypool
```

## Component Scripts

The toolkit includes the following micro-scripts:

| Script | Description |
|--------|-------------|
| `terraform_list_volumes.sh` | Lists all DigitalOcean volumes in a specific region |
| `terraform_get_droplet_metadata.sh` | Retrieves metadata about the current DigitalOcean droplet |
| `zfs_list_disks.sh` | Lists all disks used by ZFS pools |
| `summarize_storage.sh` | Displays a summary of ZFS pools and DigitalOcean volumes |
| `find_new_disks.sh` | Finds new unformatted disks that are not part of any ZFS pool |
| `terraform_create_new_volume.sh` | Creates a new DigitalOcean volume and attaches it to a droplet |
| `zfs_create_pool.sh` | Creates a new ZFS pool using the specified disk |
| `zfs_add_stripe.sh` | Adds a new device as a stripe vdev to an existing ZFS pool |
| `zfs_add_mirror.sh` | Adds a new device as a mirror to an existing device in a ZFS pool |
| `speedtest.sh` | Performs a read/write speed test on a ZFS pool |

Each script can be run independently for specific tasks, or together via the main script for a complete workflow.

## Workflow

The main script (`main.sh`) provides a guided workflow:

1. Collects droplet metadata
2. Checks current storage status
3. Scans for new disks
4. Creates a new volume if no new disks are found
5. Offers options to:
   - Add the new disk as a stripe to an existing pool (to increase capacity)
   - Add the new disk as a mirror to an existing pool (to increase redundancy)
   - Create a new pool with the new disk
6. Displays updated storage status
7. Offers to run a speed test
8. Shows ZFS usage examples

## Usage Examples

### Create a New Volume and ZFS Pool

```bash
sudo ./main.sh --poolname datapool
```

### List Available Volumes

```bash
./terraform_list_volumes.sh
```

### Find New Disks

```bash
./find_new_disks.sh --largest
```

### Add a New Disk as a Mirror

```bash
./zfs_add_mirror.sh tank /dev/disk/by-id/scsi-0DO_Volume_volume-nyc1-02
```

### Run a Speed Test on a Pool

```bash
./speedtest.sh tank
```

## Notes

- All the scripts require root privileges
- The scripts automatically install any missing dependencies
- The main workflow is designed for DigitalOcean, but individual scripts may work on other cloud providers with minimal modifications

## Troubleshooting

- If a script fails, check the error message for details
- Make sure your DigitalOcean API token has the necessary permissions
- Verify that you're running the scripts on a DigitalOcean droplet
- Check that the required dependencies are installed

## License

This toolkit is open-source software licensed under the MIT license.
