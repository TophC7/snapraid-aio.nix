# SnapRAID AIO Nix

A NixOS package and module for the [SnapRAID AIO Script](https://github.com/auanasgheps/snapraid-aio-script) - the definitive all-in-one SnapRAID helper script for Linux.

## Overview

This package provides a properly Nix-integrated version of the SnapRAID AIO script, which automates SnapRAID operations with features like:

- Automated sync operations with safety checks
- Configurable scrub capabilities
- Email notifications
- Discord, Telegram, Pushover notifications via Apprise
- Smart drive monitoring
- Robust logging

All dependencies are properly managed through Nix, and the script is patched to work correctly within the NixOS environment.

## Installation

### As a NixOS Module

Add to your flake.nix:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    snapraid-aio = {
      url = "github:Tophc7/snapraid-aio.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, snapraid-aio, ... }: {
    # For NixOS system configuration
    nixosConfigurations.<yourhostname> = nixpkgs.lib.nixosSystem {
      # ...
      modules = [
        snapraid-aio.nixosModules.default
        # ...
        ({ ... }: {
          # Configure the service
          services.snapraid-aio = {
            enable = true;
            # Optional custom config file
            configFile = "/path/to/your/snapraid-aio.conf";
            # Optional schedule
            schedule = "daily";
          };
        })
      ];
    };
  };
}
```

## Configuration

### NixOS Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the snapraid-aio service |
| `configFile` | null or path | `null` | Path to custom configuration file (if null, uses default config) |
| `schedule` | null or string | `null` | Systemd calendar expression for scheduling (e.g., "daily" or "Mon,Thu 03:00"). If null, timer won't be enabled |

### Custom Configuration

You can create a custom configuration file based on the [original template](https://github.com/auanasgheps/snapraid-aio-script/blob/a46c7362af385eac945e86a2a0f6097dbe7ca3fb/script-config.conf). The following settings have been modified in the Nix wrapper:

- `PATH` is managed by the Nix wrapper (any PATH setting in config will be ignored)
- Paths to binaries like `apprise` are automatically handled by Nix

## Usage

### Manual Execution

```bash
# Run with default config
snapraid-aio

# Run with custom config
snapraid-aio /path/to/config.conf
```

### Scheduled Execution

When enabled via NixOS module with a schedule, the service will run automatically according to the schedule. You can also trigger it manually:

```bash
# Run the service manually
sudo systemctl start snapraid-aio.service

# Check status
sudo systemctl status snapraid-aio.service

# View logs
sudo journalctl -u snapraid-aio.service
```

## Technical Details

This Nix package:

1. Properly patches the snapraid-aio script to work within NixOS
2. Manages all dependencies through Nix
3. Provides PATH protection to prevent the script from overriding critical environment variables
4. Sets up proper temporary directories for logs and state files
5. Configures systemd services and timers for scheduled operation
6. Fixes various hardcoded paths in the original script

The script uses a multi-layered approach to ensure correct operation:
- Custom wrapper script with explicit PATH setting
- PATH protection in the main script
- wrapProgram for additional dependency management

## License

This Nix package is released under MIT. The original snapraid-aio script is under GPL-3.0 license.