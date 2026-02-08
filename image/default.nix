{ config, lib, pkgs, ... }:

let
  toplevel = config.system.build.toplevel;
in
{
  system.build.rootfsImage = pkgs.callPackage
    (pkgs.path + "/nixos/lib/make-ext4-fs.nix")
    {
      storePaths = [ toplevel ];
      compressImage = false;
      volumeLabel = "NIXOS_ROOT";
      uuid = "44444444-4444-4444-8888-888888888888";
      populateImageCommands = ''
        mkdir -p files/boot
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
          -c ${toplevel} -d ./files/boot
      '';
    };
}
