{ lib, stdenv, fetchFromGitHub, autoreconfHook, libtool, pkg-config,
  mono-gateway-libnfnetlink, mono-gateway-libnetfilter_conntrack, libpcap,
  mono-gateway-libfci, mono-gateway-libcli, mono-gateway-auto-bridge }:

let
  askSrc = fetchFromGitHub {
    owner = "we-are-mono";
    repo = "ASK";
    rev = "cac8275e43251e17afaeec2cc1b8384303b20df0";
    hash = "sha256-ChkYZLjM5yMt9S1Tib4BesaeTOC803zIMXoeUTduYEw=";
  };
in
stdenv.mkDerivation {
  pname = "cmm";
  version = "17.03.1";

  src = askSrc;
  sourceRoot = "source/cmm-17.03.1";

  nativeBuildInputs = [ autoreconfHook libtool pkg-config ];
  buildInputs = [
    mono-gateway-libnfnetlink
    mono-gateway-libnetfilter_conntrack
    libpcap
    mono-gateway-libfci
    mono-gateway-libcli
    mono-gateway-auto-bridge  # for auto_bridge.h header
  ];

  enableParallelBuilding = false;

  env.NIX_CFLAGS_COMPILE = toString [
    "-DLS1043"
    "-DFLOW_STATS"
    "-DWIFI_ENABLE"
    "-DSEC_PROFILE_SUPPORT"
    "-DUSE_QOSCONNMARK"
    "-DENABLE_INGRESS_QOS"
    "-DIPSEC_NO_FLOW_CACHE"
    "-DVLAN_FILTER"
    "-DAUTO_BRIDGE"
  ];

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

  # Generate version.h since .git is not at the expected location
  preBuild = ''
    cat > src/version.h <<'VEOF'
    /*Auto-generated file. Do not edit !*/
    #ifndef VERSION_H
    #define VERSION_H
    #define CMM_VERSION "17.03.1"
    #endif /* VERSION_H */
    VEOF
  '';

  postInstall = ''
    # Install development headers
    install -d $out/include
    install -m 0644 src/libcmm.h $out/include/
    install -m 0644 src/cmmd.h $out/include/
    install -m 0644 src/fpp.h $out/include/
  '';

  meta = {
    description = "CMM (Connection Manager Module) daemon for ASK fast path";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
