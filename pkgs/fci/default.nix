{ lib, stdenv, fetchFromGitHub, mono-gateway-kernel, mono-gateway-cdx }:

let
  kernel = mono-gateway-kernel;
  askSrc = fetchFromGitHub {
    owner = "we-are-mono";
    repo = "ASK";
    rev = "cac8275e43251e17afaeec2cc1b8384303b20df0";
    hash = "sha256-ChkYZLjM5yMt9S1Tib4BesaeTOC803zIMXoeUTduYEw=";
  };
in
stdenv.mkDerivation {
  pname = "fci";
  version = "9.00.12";

  src = askSrc;
  sourceRoot = "source/fci-9.00.12";

  nativeBuildInputs = kernel.moduleBuildDependencies;

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD \
      ARCH=arm64 \
      CROSS_COMPILE=${stdenv.cc.targetPrefix} \
      BOARD_ARCH=arm64 \
      KBUILD_EXTRA_SYMBOLS=${mono-gateway-cdx}/include/cdx/Module.symvers \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D fci.ko $out/lib/modules/${kernel.modDirVersion}/extra/fci.ko
    runHook postInstall
  '';

  meta = {
    description = "FCI (Fast path Control Interface) kernel module for ASK fast path";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
