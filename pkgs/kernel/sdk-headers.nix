# Extract NXP FMan SDK driver headers from the patched kernel source.
# These are needed by out-of-tree ASK modules (CDX, etc.) but are stripped
# from the kernel dev output by nixpkgs to save space.
{ stdenv, fetchFromGitHub }:

let
  kernelSrc = fetchFromGitHub {
    owner = "nxp-qoriq";
    repo = "linux";
    rev = "df24f9428e38740256a410b983003a478e72a7c0";
    hash = "sha256-+cYjZ26Hx4tGR1tVz4p47TF4HG/9IS1tDnLIDDWsRFA=";
  };
in
stdenv.mkDerivation {
  pname = "nxp-kernel-sdk-headers";
  version = "6.12.49";

  src = kernelSrc;

  patches = [
    ./patches/002-mono-gateway-ask-kernel_linux_6_12.patch
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/drivers/net/ethernet/freescale
    cp -r drivers/net/ethernet/freescale/sdk_fman $out/drivers/net/ethernet/freescale/
    cp -r drivers/net/ethernet/freescale/sdk_dpaa $out/drivers/net/ethernet/freescale/
    mkdir -p $out/drivers/crypto
    cp -r drivers/crypto/caam $out/drivers/crypto/
  '';

  meta.platforms = [ "aarch64-linux" "x86_64-linux" ];
}
