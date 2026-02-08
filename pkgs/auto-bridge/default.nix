{ lib, stdenv, mono-gateway-kernel }:

let
  kernel = mono-gateway-kernel;
in
stdenv.mkDerivation {
  pname = "auto-bridge";
  version = "6.02.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./auto_bridge.c
      ./auto_bridge_private.h
      ./Makefile
      ./include
    ];
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD \
      ARCH=arm64 \
      CROSS_COMPILE=${stdenv.cc.targetPrefix} \
      PLATFORM=LS1043A \
      ENABLE_VLAN_FILTER=y \
      KERNEL_SOURCE=${kernel.dev}/lib/modules/${kernel.modDirVersion}/source \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D auto_bridge.ko $out/lib/modules/${kernel.modDirVersion}/extra/auto_bridge.ko
    install -D include/auto_bridge.h $out/include/auto_bridge.h
    runHook postInstall
  '';

  meta = {
    description = "Auto bridge kernel module for ASK fast path";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
