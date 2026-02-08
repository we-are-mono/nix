{ lib, stdenv, mono-gateway-kernel }:

let
  kernel = mono-gateway-kernel;
in
stdenv.mkDerivation {
  pname = "sfp-led";
  version = "1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./sfp-led.c
      ./Makefile
    ];
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD \
      ARCH=arm64 \
      CROSS_COMPILE=${stdenv.cc.targetPrefix} \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D sfp-led.ko $out/lib/modules/${kernel.modDirVersion}/extra/sfp-led.ko
    runHook postInstall
  '';

  meta = {
    description = "SFP LED control kernel module for Mono Gateway";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
