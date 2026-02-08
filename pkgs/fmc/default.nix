{ lib, stdenv, fetchFromGitHub, mono-gateway-fmlib, libxml2, tclap }:

stdenv.mkDerivation {
  pname = "fmc";
  version = "6.12.49-2.2.0";

  src = fetchFromGitHub {
    owner = "nxp-qoriq";
    repo = "fmc";
    rev = "5b9f4b16a864e9dfa58cdcc860be278a7f66ac18";
    hash = "sha256-hGxQJ4pDkqN/P7cONivcNn9t6p7l1af8SoEPVBYiPFk=";
  };

  # Convert CRLF to LF before patching (upstream has Windows line endings)
  prePatch = ''
    for f in source/*.cpp source/*.h source/spa/*.c source/spa/*.h; do
      if [ -f "$f" ]; then
        sed -i 's/\r$//' "$f"
      fi
    done
  '';

  patches = [
    ./01-mono-ask-extensions.patch
  ];

  buildInputs = [ mono-gateway-fmlib libxml2 tclap ];

  enableParallelBuilding = false;

  makeFlags = [
    "-C" "source"
    "MACHINE=ls1046"
    "FMD_USPACE_HEADER_PATH=${mono-gateway-fmlib}/include/fmd"
    "FMD_USPACE_LIB_PATH=${mono-gateway-fmlib}/lib"
    "LIBXML2_HEADER_PATH=${libxml2.dev}/include/libxml2"
    "TCLAP_HEADER_PATH=${tclap}/include"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 source/fmc $out/bin/fmc
    install -Dm644 source/fmc.h $out/include/fmc/fmc.h
    install -Dm644 source/libfmc.a $out/lib/libfmc.a

    if [ -d etc/fmc/config ]; then
      install -d $out/etc/fmc/config
      install -m644 etc/fmc/config/* $out/etc/fmc/config/
    fi

    runHook postInstall
  '';

  meta = {
    description = "NXP Frame Manager Configuration tool";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.mit;
  };
}
