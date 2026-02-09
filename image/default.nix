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
      uuid = "39e0cc49-d11a-4e30-a782-8baf2fd64ed7";
      populateImageCommands = ''
        mkdir -p files/boot
        ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
          -c ${toplevel} -d ./files/boot
      '';
    };
}
