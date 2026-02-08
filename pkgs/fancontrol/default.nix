# Fancontrol uses nixpkgs' lm_sensors package.
# This directory only holds the custom fancontrol.conf for the Mono Gateway.
# The config is applied in the NixOS configuration module (Phase 7).
throw "This package is not meant to be built. Use pkgs.lm_sensors and reference ./fancontrol.conf in the NixOS module."
