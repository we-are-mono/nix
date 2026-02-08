{ lib, stdenv, mono-gateway-kernel }:

let
  kernel = mono-gateway-kernel;
in
stdenv.mkDerivation {
  pname = "lp5812-driver";
  version = "1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./leds-lp5812.c
      ./leds-lp5812.h
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
    install -D leds-lp5812.ko $out/lib/modules/${kernel.modDirVersion}/extra/leds-lp5812.ko
    runHook postInstall
  '';

  meta = {
    description = "Texas Instruments LP5812 LED Matrix Driver";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Only;
  };
}
