{ lib, stdenv, fetchFromGitHub, autoreconfHook, libtool, pkg-config }:

let
  askSrc = fetchFromGitHub {
    owner = "we-are-mono";
    repo = "ASK";
    rev = "cac8275e43251e17afaeec2cc1b8384303b20df0";
    hash = "sha256-ChkYZLjM5yMt9S1Tib4BesaeTOC803zIMXoeUTduYEw=";
  };
in
stdenv.mkDerivation {
  pname = "libfci";
  version = "9.00.12";

  src = askSrc;
  sourceRoot = "source/fci-9.00.12/lib";

  nativeBuildInputs = [ autoreconfHook libtool pkg-config ];

  # automake requires README — must exist before autoreconfHook runs
  postUnpack = ''
    touch $sourceRoot/README
  '';

  # clean leftover build files before configure
  preConfigure = ''
    if [ -f Makefile ]; then
      make distclean || true
    fi
    rm -f config.log config.status
  '';

  postInstall = ''
    install -d $out/include
    install -m 0644 include/libfci.h $out/include/
  '';

  meta = {
    description = "FCI userspace library for ASK fast path";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
