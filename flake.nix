{
  description = "The definitive all-in-one SnapRAID script on Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    snapraid-aio-src = {
      url = "github:auanasgheps/snapraid-aio-script/a46c7362af385eac945e86a2a0f6097dbe7ca3fb"; # v3.4-beta3
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      snapraid-aio-src,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        dependencies = with pkgs; [
          apprise
          bash
          bc
          coreutils
          curl
          findutils
          gnugrep
          gnused
          hostname # Added for the hostname command
          jq
          mailutils # For mailx
          procps
          (python3.withPackages (ps: with ps; [ markdown ])) # Fixed Python with markdown module
          python3Packages.pipx
          smartmontools # For smartctl
          snapraid
          util-linux # For lsblk
        ];
      in
      {
        packages = rec {
          default = snapraid-aio;

          snapraid-aio = pkgs.stdenv.mkDerivation rec {
            pname = "snapraid-aio";
            version = "3.4-beta3";
            src = snapraid-aio-src;

            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = dependencies;

            dontBuild = true;

            installPhase = ''
              # Create directories
              mkdir -p $out/bin
              mkdir -p $out/share/snapraid-aio

              # 1. PATCH CONFIG: Modify the config file to not overwrite PATH
              cat script-config.conf | sed 's|^PATH=.*$|# PATH is managed by Nix wrapper|' > $out/share/snapraid-aio/default-config.conf
              cp README.md $out/share/snapraid-aio/

              # 2. PATCH SCRIPT: Add PATH protection to the main script and fix paths
              cat snapraid-aio-script.sh > temp_script.sh

              # Insert code to save PATH before sourcing config
              sed -i '/#shellcheck source=script-config.conf/i # Save original PATH\nORIGINAL_PATH="$PATH"' temp_script.sh

              # Insert code to restore PATH after sourcing config 
              sed -i '/source "$CONFIG_FILE"/a # Restore original PATH\nPATH="$ORIGINAL_PATH"' temp_script.sh

              # Fix the process substitution issue
              sed -i 's/exec > >(tee/exec > >(PATH="$PATH" tee/g' temp_script.sh

              # Fix specific command paths
              sed -i 's|MAIL_BIN=/usr/bin/mailx|MAIL_BIN=${pkgs.mailutils}/bin/mailx|g' temp_script.sh
              sed -i 's|command -v dpkg >/dev/null|false|g' temp_script.sh
              sed -i 's|python3 -m markdown|${
                pkgs.python3.withPackages (ps: with ps; [ markdown ])
              }/bin/python3 -m markdown|g' temp_script.sh

              # Copy the patched script
              cp temp_script.sh $out/share/snapraid-aio/snapraid-aio-script.sh
              chmod +x $out/share/snapraid-aio/snapraid-aio-script.sh
              rm temp_script.sh

              # 3. EXPLICIT PATH IN WRAPPER: Create wrapper script with explicit PATH setting
              cat > $out/bin/snapraid-aio << EOF
              #!${pkgs.bash}/bin/bash

              # Set PATH explicitly to include all dependencies
              export PATH="${pkgs.lib.makeBinPath dependencies}:$PATH"

              # Create a writable temp directory if needed
              TEMP_DIR="\$HOME/.cache/snapraid-aio"
              mkdir -p "\$TEMP_DIR"

              # Define default config path
              DEFAULT_CONFIG="$out/share/snapraid-aio/default-config.conf"

              # Export environment variables the script needs
              export TMP_OUTPUT="\$TEMP_DIR/snapRAID.out"
              export SYNC_WARN_FILE="\$TEMP_DIR/snapRAID.warnCount"
              export SCRUB_COUNT_FILE="\$TEMP_DIR/snapRAID.scrubCount"

              # If user specified a config, use it
              if [ "\$1" ] && [ -f "\$1" ]; then
                exec ${pkgs.bash}/bin/bash $out/share/snapraid-aio/snapraid-aio-script.sh "\$@"
                exit 0
              fi

              # Otherwise use the default config
              exec ${pkgs.bash}/bin/bash $out/share/snapraid-aio/snapraid-aio-script.sh "\$DEFAULT_CONFIG" "\$@"
              EOF
              chmod +x $out/bin/snapraid-aio

              # Still use wrapProgram as a 4th layer of protection
              wrapProgram $out/share/snapraid-aio/snapraid-aio-script.sh \
                --prefix PATH : ${pkgs.lib.makeBinPath dependencies}
            '';

            meta = with pkgs.lib; {
              description = "All-in-one SnapRAID helper script";
              homepage = "https://github.com/auanasgheps/snapraid-aio-script";
              license = licenses.gpl3;
              platforms = platforms.linux;
            };
          };

        };
      }
    )
    // {
      # NixOS module for system-wide installation
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        with lib;
        let
          cfg = config.services.snapraid-aio;
        in
        {
          options.services.snapraid-aio = {
            enable = mkEnableOption "snapraid-aio script";

            configFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Path to custom snapraid-aio configuration file";
            };

            schedule = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "daily";
              description = "Systemd calendar expression for when to run snapraid-aio. If null, timer won't be enabled.";
            };
          };

          config = mkIf cfg.enable {
            environment.systemPackages = [ self.packages.${pkgs.system}.default ];

            systemd.services.snapraid-aio = {
              description = "SnapRAID maintenance with snapraid-aio";
              serviceConfig = {
                Type = "oneshot";
                ExecStart =
                  if cfg.configFile != null then
                    "${self.packages.${pkgs.system}.default}/bin/snapraid-aio ${cfg.configFile}"
                  else
                    "${self.packages.${pkgs.system}.default}/bin/snapraid-aio";
              };
            };

            systemd.timers.snapraid-aio = mkIf (cfg.schedule != null) {
              description = "Run snapraid-aio on schedule";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = cfg.schedule;
                Persistent = true;
              };
            };
          };
        };
    };
}