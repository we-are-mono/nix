{ lib, stdenv, fetchFromGitHub, libxml2,
  mono-gateway-libcli, mono-gateway-fmc, mono-gateway-fmlib }:

let
  askSrc = fetchFromGitHub {
    owner = "we-are-mono";
    repo = "ASK";
    rev = "cac8275e43251e17afaeec2cc1b8384303b20df0";
    hash = "sha256-ChkYZLjM5yMt9S1Tib4BesaeTOC803zIMXoeUTduYEw=";
  };
in
stdenv.mkDerivation {
  pname = "dpa-app";
  version = "4.03.0";

  src = askSrc;
  sourceRoot = "source/dpa_app-4.03.0";

  buildInputs = [
    libxml2
    mono-gateway-libcli
    mono-gateway-fmc
    mono-gateway-fmlib
  ];

  # Get cdx_ioctl.h from ASK source tree (avoids circular dep with CDX kernel module)
  postUnpack = ''
    mkdir -p $sourceRoot/cdx_include
    cp source/cdx-5.03.1/cdx_ioctl.h $sourceRoot/cdx_include/
  '';

  env.NIX_CFLAGS_COMPILE = toString [
    "-DENDIAN_LITTLE"
    "-DLS1043"
    "-DNCSW_LINUX"
    "-DDPAA_DEBUG_ENABLE"
    "-DSEC_PROFILE_SUPPORT"
    "-DVLAN_FILTER"
    "-I${mono-gateway-fmc}/include/fmc"
    "-I${mono-gateway-fmlib}/include/fmd"
    "-I${mono-gateway-fmlib}/include/fmd/integrations"
    "-I${mono-gateway-fmlib}/include/fmd/Peripherals"
    "-I${mono-gateway-fmlib}/include/fmd/Peripherals/common"
    "-Icdx_include"
  ];

  # No configure step
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    make CC="${stdenv.cc.targetPrefix}cc" \
      CFLAGS="$NIX_CFLAGS_COMPILE" \
      LDFLAGS="-L${mono-gateway-fmc}/lib -L${mono-gateway-fmlib}/lib -L${mono-gateway-libcli}/lib -Wl,--as-needed -lfmc -lfm-arm -lstdc++ -lxml2 -lpthread -lcli"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D dpa_app $out/bin/dpa_app

    # Install XML configuration files
    install -d $out/etc
    install -m 0644 files/etc/*.xml $out/etc/

    # Override cdx_cfg.xml with Mono Gateway DK specific config
    install -m 0644 ${./cdx_cfg.xml} $out/etc/cdx_cfg.xml
    runHook postInstall
  '';

  meta = {
    description = "DPA App for ASK fast path offload management";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
