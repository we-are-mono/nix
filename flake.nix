{
  description = "NixOS for Mono Gateway Development Kit (LS1046A)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      overlay = final: prev: {
        mono-gateway-kernel = final.callPackage ./pkgs/kernel { };
        mono-gateway-sdk-headers = final.callPackage ./pkgs/kernel/sdk-headers.nix { };
        mono-gateway-fmlib = final.callPackage ./pkgs/fmlib { };
        mono-gateway-fmc = final.callPackage ./pkgs/fmc { };
        mono-gateway-sfp-led = final.callPackage ./pkgs/sfp-led { };
        mono-gateway-lp5812-driver = final.callPackage ./pkgs/lp5812-driver { };
        mono-gateway-status-led = final.callPackage ./pkgs/status-led { };
        mono-gateway-libnfnetlink = prev.libnfnetlink.overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            ./pkgs/cmm/01-nxp-ask-nonblocking-heap-buffer.patch
          ];
        });
        mono-gateway-libnetfilter_conntrack = (prev.libnetfilter_conntrack.override {
          libnfnetlink = final.mono-gateway-libnfnetlink;
        }).overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            ./pkgs/cmm/01-nxp-ask-comcerto-fp-extensions.patch
          ];
        });
        mono-gateway-libcli = final.callPackage ./pkgs/libcli { };
        mono-gateway-auto-bridge = final.callPackage ./pkgs/auto-bridge { };
        mono-gateway-cdx = final.callPackage ./pkgs/cdx { };
        mono-gateway-fci = final.callPackage ./pkgs/fci { };
        mono-gateway-libfci = final.callPackage ./pkgs/libfci { };
        mono-gateway-cmm = final.callPackage ./pkgs/cmm { };
        mono-gateway-dpa-app = final.callPackage ./pkgs/dpa-app { };
      };

      # Cross-compiled pkgs for building individual packages on x86_64
      crossPkgs = import nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = "aarch64-linux";
        overlays = [ overlay ];
      };
    in
    {
      overlays.default = overlay;

      # Cross-compiled from x86_64 host
      nixosConfigurations.gateway = nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.overlays = [ overlay ]; }
          {
            nixpkgs.localSystem.system = "x86_64-linux";
            nixpkgs.crossSystem.system = "aarch64-linux";
          }
          ./configurations/gateway.nix
          ./image/default.nix
        ];
      };

      # Native build on aarch64
      nixosConfigurations.gateway-native = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          { nixpkgs.overlays = [ overlay ]; }
          ./configurations/gateway.nix
          ./image/default.nix
        ];
      };

      # Basic build checks (run with: nix flake check)
      checks.x86_64-linux = {
        # Verify the NixOS configuration evaluates without errors
        gatewayToplevel = self.nixosConfigurations.gateway.config.system.build.toplevel;
      };

      # Individual packages (cross-compiled from x86_64)
      packages.aarch64-linux = {
        kernel = crossPkgs.mono-gateway-kernel;
        fmlib = crossPkgs.mono-gateway-fmlib;
        fmc = crossPkgs.mono-gateway-fmc;
        sfp-led = crossPkgs.mono-gateway-sfp-led;
        lp5812-driver = crossPkgs.mono-gateway-lp5812-driver;
        status-led = crossPkgs.mono-gateway-status-led;
        libcli = crossPkgs.mono-gateway-libcli;
        auto-bridge = crossPkgs.mono-gateway-auto-bridge;
        cdx = crossPkgs.mono-gateway-cdx;
        fci = crossPkgs.mono-gateway-fci;
        libfci = crossPkgs.mono-gateway-libfci;
        cmm = crossPkgs.mono-gateway-cmm;
        dpa-app = crossPkgs.mono-gateway-dpa-app;
        rootfsImage = self.nixosConfigurations.gateway.config.system.build.rootfsImage;
      };
    };
}
