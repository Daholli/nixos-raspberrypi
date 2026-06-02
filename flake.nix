{
  description = "Flake for RaspberryPi support on NixOS";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    argononed = {
      # url = "git+file:../argononed?shallow=1";
      # url = "git+https://gitlab.com/DarkElvenAngel/argononed.git";
      url = "github:nvmd/argononed";
      flake = false;
    };

    nixos-images = {
      # url = "github:nix-community/nixos-images";
      url = "github:nvmd/nixos-images/sdimage-installer";
      # url = "git+file:../nixos-images?shallow=1";
      inputs.nixos-stable.follows = "nixpkgs";
      inputs.nixos-unstable.follows = "nixpkgs";
    };

    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs =
    {
      self,
      nixpkgs,
      argononed,
      nixos-images,
      ...
    }@inputs:
    let
      rpiSystems = [
        "aarch64-linux"
        "armv7l-linux"
        "armv6l-linux"
      ];
      allSystems = nixpkgs.lib.systems.flakeExposed;
      forSystems = systems: f: nixpkgs.lib.genAttrs systems f;
      mkRpiPkgs =
        nixpkgs: system:
        import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.pkgs

            self.overlays.bootloader
            self.overlays.vendor-kernel
            self.overlays.vendor-firmware
            self.overlays.kernel-and-firmware

            self.overlays.vendor-pkgs
          ];
        };
      mkLegacyPackagesFor = nixpkgs: forSystems rpiSystems (mkRpiPkgs nixpkgs);
    in
    {
      formatter = forSystems allSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      devShells = forSystems allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            name = "nixos-raspberrypi";
            nativeBuildInputs = with pkgs; [
              nil # lsp language server for nix
              nixfmt-tree
              nix-output-monitor
              bash-language-server
              shellcheck
              (pkgs.callPackage ./devshells/nix-build-to-cachix.nix { })
              gh
            ];
          };
        }
      );

      lib = import ./lib (
        {
          inherit (nixpkgs) lib;
        }
        // inputs
      );

      nixosModules = {
        trusted-nix-caches = import ./modules/trusted-nix-caches.nix;
        nixpkgs-rpi = import ./modules/nixpkgs-rpi.nix;

        bootloader = import ./modules/system/boot/loader/raspberrypi;
        default = import ./modules/raspberrypi.nix;

        sd-image = import ./modules/installer/sd-card/sd-image-raspberrypi.nix;

        pisugar-3 = import ./modules/pisugar-3.nix;

        usb-gadget-ethernet = import ./modules/usb-gadget-ethernet.nix;

        raspberry-pi-5 = {
          base = import ./modules/raspberry-pi-5;
          display-vc4 = import ./modules/display-vc4.nix;
          display-rp1 = import ./modules/raspberry-pi-5/display-rp1.nix;
          bluetooth = import ./modules/bluetooth.nix;
          page-size-16k = import ./modules/raspberry-pi-5/page-size-16k.nix;
        };

        raspberry-pi-4 = {
          base = import ./modules/raspberry-pi-4.nix;
          display-vc4 = import ./modules/display-vc4.nix;
          bluetooth = import ./modules/bluetooth.nix;
          # work-in-progress, untested
          case-argonone = import ./modules/case-argononev2.nix { inherit argononed; };
        };

        raspberry-pi-3 = {
          base = import ./modules/raspberry-pi-3.nix;
        };

        raspberry-pi-02 = {
          base = import ./modules/raspberry-pi-02.nix;
          display-vc4 = import ./modules/display-vc4.nix;
          bluetooth = import ./modules/bluetooth.nix;
        };
      };

      overlays = {
        bootloader = import ./overlays/bootloader.nix;

        pkgs = import ./overlays/pkgs.nix;
        vendor-pkgs = import ./overlays/vendor-pkgs.nix;
        jemalloc-page-size-16k = import ./overlays/jemalloc-page-size-16k.nix;

        vendor-firmware = import ./overlays/vendor-firmware.nix;
        vendor-kernel = import ./overlays/vendor-kernel.nix;

        kernel-and-firmware = import ./overlays/linux-and-firmware.nix;

        libpisp-default-config-path = import ./overlays/libpisp-default-config-path.nix;
      };

      # "RPi world": nixpkgs with all overlays applied "globally", i.e.
      # all packages here depend on rpi's/optimized versions of the dependencies
      # * used inside the modules, where a choice of "sane defaults" about the
      #   nixpkgs channel had to be made
      # * binary cache is generated from this package set
      legacyPackages = mkLegacyPackagesFor nixpkgs;

      packages = forSystems rpiSystems (
        system:
        let
          pkgs = self.legacyPackages.${system};
        in
        {
          inherit (pkgs) ffmpeg_4;
          inherit (pkgs) ffmpeg_6;
          inherit (pkgs) ffmpeg_7;
          inherit (pkgs) ffmpeg_7-headless;
          inherit (pkgs) ffmpeg_8;
          inherit (pkgs) ffmpeg_8-headless;

          inherit (pkgs) kodi;
          inherit (pkgs) kodi-gbm;
          inherit (pkgs) kodi-wayland;

          inherit (pkgs) libcamera;
          inherit (pkgs) libpisp;
          inherit (pkgs) libraspberrypi;

          inherit (pkgs) raspberrypi-utils;
          raspberrypi-udev-rules = pkgs.callPackage ./pkgs/raspberrypi/udev-rules.nix { };
          inherit (pkgs) rpicam-apps;

          inherit (pkgs) vlc;

          # see legacyPackages.<system>.linuxAndFirmware for other versions of
          # the bundle
          inherit (pkgs.linuxAndFirmware.default)
            linux_rpi5
            linuxPackages_rpi5
            linux_rpi4
            linuxPackages_rpi4
            linux_rpi3
            linuxPackages_rpi3
            linux_rpi02
            linuxPackages_rpi02
            raspberrypifw
            raspberrypiWirelessFirmware
            ;

          argononed = pkgs.callPackage "${inputs.argononed}/OS/nixos/pkg.nix" { };

          pisugar3-kmod =
            let
              targetKernel = pkgs.linux_rpi02;
            in
            (pkgs.linuxPackagesFor targetKernel).callPackage ./pkgs/pisugar-kmod.nix {
              pisugarVersion = "3";
            };
          pisugar2-kmod =
            let
              targetKernel = pkgs.linux_rpi02;
            in
            (pkgs.linuxPackagesFor targetKernel).callPackage ./pkgs/pisugar-kmod.nix {
              pisugarVersion = "2";
            };

          pisugar-power-manager-rs = pkgs.callPackage ./pkgs/pisugar-power-manager-rs.nix { };

        }
      );

      nixosConfigurations =
        let

          # TIP: To create "regular" nixosConfigurations look for
          # `nixosSystem` and `nixosSystemFull` helpers in `lib/`
          mkNixOSRPiInstaller =
            modules:
            self.lib.nixosInstaller {
              specialArgs = inputs // {
                nixos-raspberrypi = self;
              };
              modules = [
                nixos-images.nixosModules.sdimage-installer
                (
                  {
                    config,
                    lib,
                    modulesPath,
                    ...
                  }:
                  {
                    disabledModules = [
                      # disable the sd-image module that nixos-images uses
                      (modulesPath + "/installer/sd-card/sd-image-aarch64-installer.nix")
                    ];
                    # nixos-images sets this with `mkForce`, thus `mkOverride 40`
                    image.baseName =
                      let
                        cfg = config.boot.loader.raspberry-pi;
                      in
                      lib.mkOverride 40 "nixos-installer-rpi${cfg.variant}-${cfg.bootloader}";
                  }
                )
              ]
              ++ modules;
            };

          custom-user-config =
            {
              config,
              pkgs,
              lib,
              ...
            }:
            {
              users.users.remotebuild = {
                isNormalUser = true;
                createHome = false;
                group = "remotebuild";

                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYZjG+XPNoVHVdCel5MK4mwvtoFCqDY1WMI1yoU71Rd root@yggdrasil"
                ];
              };

              users.groups.remotebuild = { };

              nix = {
                nrBuildUsers = 64;
                settings = {
                  trusted-users = [ "remotebuild" ];

                  min-free = 10 * 1024 * 1024;
                  max-free = 200 * 1024 * 1024;

                  max-jobs = "auto";
                  cores = 0;
                };
              };

              systemd.services.nix-daemon.serviceConfig = {
                MemoryAccounting = true;
                MemoryMax = "90%";
                OOMScoreAdjust = 500;
                Slice = "-.slice";
              };

              users.users.nixos.openssh.authorizedKeys.keys = [
                # YOUR SSH PUB KEY HERE #
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFrDiO5+vMfD5MimkzN32iw3MnSMLZ0mHvOrHVVmLD0"

              ];
              users.users.root.openssh.authorizedKeys.keys = [
                # YOUR SSH PUB KEY HERE #
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFrDiO5+vMfD5MimkzN32iw3MnSMLZ0mHvOrHVVmLD0"

              ];

              environment.systemPackages = with pkgs; [
                tree
              ];

              networking.wireless.enable = lib.mkForce false;

              system.nixos.tags =
                let
                  cfg = config.boot.loader.raspberry-pi;
                in
                [
                  "raspberry-pi-${cfg.variant}"
                  cfg.bootloader
                  config.boot.kernelPackages.kernel.version
                ];
            };

        in
        {

          rpi02-installer = mkNixOSRPiInstaller [
            (
              {
                nixos-raspberrypi,
                ...
              }:
              {
                imports = with nixos-raspberrypi.nixosModules; [
                  # Hardware configuration
                  raspberry-pi-02.base
                  usb-gadget-ethernet
                ];
              }
            )
            custom-user-config
          ];

          rpi3-installer = mkNixOSRPiInstaller [
            (
              {
                nixos-raspberrypi,
                ...
              }:
              {
                imports = with nixos-raspberrypi.nixosModules; [
                  # Hardware configuration
                  raspberry-pi-3.base
                ];
              }
            )
            custom-user-config
          ];

          rpi4-installer = mkNixOSRPiInstaller [
            (
              {
                nixos-raspberrypi,
                ...
              }:
              {
                imports = with nixos-raspberrypi.nixosModules; [
                  # Hardware configuration
                  raspberry-pi-4.base
                ];
              }
            )
            custom-user-config
          ];

          rpi5-installer = mkNixOSRPiInstaller [
            (
              {
                nixos-raspberrypi,
                ...
              }:
              {
                imports = with nixos-raspberrypi.nixosModules; [
                  # Hardware configuration
                  raspberry-pi-5.base
                  raspberry-pi-5.page-size-16k
                ];
              }
            )
            custom-user-config
          ];

        };

      installerImages =
        let
          nixos = self.nixosConfigurations;
          mkImage = nixosConfig: nixosConfig.config.system.build.sdImage;
        in
        {
          rpi02 = mkImage nixos.rpi02-installer;
          rpi3 = mkImage nixos.rpi3-installer;
          rpi4 = mkImage nixos.rpi4-installer;
          rpi5 = mkImage nixos.rpi5-installer;
        };

    };
}
