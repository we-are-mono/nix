{ lib, stdenv, fetchFromGitHub, libxcrypt, pkg-config }:

stdenv.mkDerivation rec {
  pname = "libcli";
  version = "1.10.0";

  src = fetchFromGitHub {
    owner = "dparrish";
    repo = "libcli";
    rev = "6a3b2f96c4f0916e2603a96bf24d704f6a904e7a";
    hash = "sha256-xGAJytBGJl/+gz0S3xMhd/UJlF7iOJuP3DYNMuVpCmY=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libxcrypt ];

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "AR=${stdenv.cc.targetPrefix}ar"
    "PREFIX=${placeholder "out"}"
    "DESTDIR="
  ];

  env.NIX_CFLAGS_COMPILE = "-Wno-calloc-transposed-args";

  installFlags = [
    "PREFIX=${placeholder "out"}"
    "DESTDIR="
  ];

  meta = {
    description = "Cisco-like command-line interface library";
    homepage = "https://github.com/dparrish/libcli";
    license = lib.licenses.lgpl21Only;
    platforms = [ "aarch64-linux" ];
  };
}
