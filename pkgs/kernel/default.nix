{ lib, fetchFromGitHub, linuxManualConfig, ... }:

(linuxManualConfig {
  version = "6.12.49";
  modDirVersion = "6.12.49";

  src = fetchFromGitHub {
    owner = "nxp-qoriq";
    repo = "linux";
    rev = "df24f9428e38740256a410b983003a478e72a7c0";
    hash = "sha256-+cYjZ26Hx4tGR1tVz4p47TF4HG/9IS1tDnLIDDWsRFA=";
  };

  configfile = ./defconfig;
  allowImportFromDerivation = true;

  kernelPatches = [
    { name = "001-ina234"; patch = ./patches/001-hwmon-ina2xx-Add-INA234-support.patch; }
    { name = "002-ask-offload"; patch = ./patches/002-mono-gateway-ask-kernel_linux_6_12.patch; }
    { name = "003-fman-aliases"; patch = ./patches/003-fman-respect-ethernet-aliases.patch; }
  ];

  extraMeta.platforms = [ "aarch64-linux" ];
}).overrideAttrs (old: {
  # Copy custom device trees into kernel source tree before build
  postPatch = (old.postPatch or "") + ''
    cp ${./dts}/*.dts arch/arm64/boot/dts/freescale/
    echo 'dtb-$(CONFIG_ARCH_LAYERSCAPE) += mono-gateway-dk.dtb' >> arch/arm64/boot/dts/freescale/Makefile
    echo 'dtb-$(CONFIG_ARCH_LAYERSCAPE) += mono-gateway-dk-sdk.dtb' >> arch/arm64/boot/dts/freescale/Makefile
  '';
})
