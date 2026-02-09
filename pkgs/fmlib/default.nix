{ lib, stdenv, fetchFromGitHub, mono-gateway-kernel }:

let
  kernel = mono-gateway-kernel;
in
stdenv.mkDerivation {
  pname = "fmlib";
  version = "6.12.49-2.2.0";

  src = fetchFromGitHub {
    owner = "nxp-qoriq";
    repo = "fmlib";
    rev = "7a58ecaf0d90d71d6b78d3ac7998282a472c4394";
    hash = "sha256-ag2kzedhOwXRqXZsL0yHcokbOFldvmf5paJPPfrzUzo=";
  };

  patches = [
    ./01-mono-ask-extensions.patch
  ];

  env = {
    CROSS_COMPILE = stdenv.cc.targetPrefix;
    KERNEL_SRC = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source";
  };

  makeFlags = [ "libfm-arm.a" ];

  installPhase = ''
    runHook preInstall
    make install-libfm-arm \
      DESTDIR=$out \
      PREFIX=/ \
      LIB_DEST_DIR=/lib
    rm -rf $out/usr/src
    runHook postInstall
  '';

  meta = {
    description = "NXP Frame Manager userspace library";
    platforms = [ "aarch64-linux" ];
    license = with lib.licenses; [ bsd3 gpl2Only ];
  };
}
