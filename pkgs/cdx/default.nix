{ lib, stdenv, fetchFromGitHub, mono-gateway-kernel, mono-gateway-sdk-headers, mono-gateway-dpa-app }:

let
  kernel = mono-gateway-kernel;
  sdkHeaders = mono-gateway-sdk-headers;

  askSrc = fetchFromGitHub {
    owner = "we-are-mono";
    repo = "ASK";
    rev = "cac8275e43251e17afaeec2cc1b8384303b20df0";
    hash = "sha256-ChkYZLjM5yMt9S1Tib4BesaeTOC803zIMXoeUTduYEw=";
  };

  fmanDir = "${sdkHeaders}/drivers/net/ethernet/freescale/sdk_fman";
  dpaaDir = "${sdkHeaders}/drivers/net/ethernet/freescale/sdk_dpaa";
  caamDir = "${sdkHeaders}/drivers/crypto/caam";
  kernelDevSrc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source";
in
stdenv.mkDerivation {
  pname = "cdx";
  version = "5.03.1";

  src = askSrc;
  sourceRoot = "source/cdx-5.03.1";

  nativeBuildInputs = kernel.moduleBuildDependencies;

  postUnpack = ''
    # Patch hardcoded /usr/bin/dpa_app path to Nix store path
    substituteInPlace $sourceRoot/cdx_main.c \
      --replace-fail '/usr/bin/dpa_app' '${mono-gateway-dpa-app}/bin/dpa_app'

    # Replace ncsw_config.mk include with direct ccflags-y entries.
    # The Makefile includes $(srctree)/drivers/.../ncsw_config.mk but the kernel dev
    # output doesn't have drivers/. We provide the same flags with explicit paths
    # to the patched SDK headers derivation.
    substituteInPlace $sourceRoot/Makefile \
      --replace-fail 'include $(srctree)/drivers/net/ethernet/freescale/fman/ncsw_config.mk' '# ncsw_config.mk replaced by Nix' \
      --replace-fail 'include $(srctree)/drivers/net/ethernet/freescale/sdk_fman/ncsw_config.mk' '# ncsw_config.mk replaced by Nix'

    # Also fix the FMAN_DRIVER_PATH references (used for src/wrapper include)
    substituteInPlace $sourceRoot/Makefile \
      --replace-fail 'FMAN_DRIVER_PATH = $(srctree)/drivers/net/ethernet/freescale/fman' 'FMAN_DRIVER_PATH = ${fmanDir}' \
      --replace-fail 'FMAN_DRIVER_PATH = $(srctree)/drivers/net/ethernet/freescale/sdk_fman' 'FMAN_DRIVER_PATH = ${fmanDir}'

    # Replace caam include path
    substituteInPlace $sourceRoot/Makefile \
      --replace-fail '-I$(srctree)/drivers/crypto/caam' '-I${caamDir}'

    cat >> $sourceRoot/Makefile <<MKEOF

# NXP FMan SDK include paths (replaces ncsw_config.mk)
ccflags-y += -include ${fmanDir}/ls1043_dflags.h
ccflags-y += -I${dpaaDir}/
ccflags-y += -I${fmanDir}/inc
ccflags-y += -I${fmanDir}/inc/cores
ccflags-y += -I${fmanDir}/inc/etc
ccflags-y += -I${fmanDir}/inc/Peripherals
ccflags-y += -I${fmanDir}/inc/flib
ccflags-y += -I${fmanDir}/inc/integrations/LS1043
ccflags-y += -I${fmanDir}/src/inc
ccflags-y += -I${fmanDir}/src/inc/system
ccflags-y += -I${fmanDir}/src/inc/wrapper
ccflags-y += -I${fmanDir}/src/inc/xx
ccflags-y += -I${kernelDevSrc}/include/uapi/linux/fmd
ccflags-y += -I${kernelDevSrc}/include/uapi/linux/fmd/Peripherals
ccflags-y += -I${kernelDevSrc}/include/uapi/linux/fmd/integrations
MKEOF
  '';

  # Generate version.h since .git is not at the expected location
  preBuild = ''
    cat > version.h <<'VEOF'
/*Auto-generated file. Do not edit !*/
#ifndef CDX_VERSION_H
#define CDX_VERSION_H
#define CDX_VERSION "5.03.1"
#endif /* CDX_VERSION_H */
VEOF
  '';

  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$PWD \
      ARCH=arm64 \
      CROSS_COMPILE=${stdenv.cc.targetPrefix} \
      KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      'CFG_FLAGS=-DSEC_PROFILE_SUPPORT -DVLAN_FILTER -DWIFI_ENABLE -DENABLE_EGRESS_QOS' \
      modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -D cdx.ko $out/lib/modules/${kernel.modDirVersion}/extra/cdx.ko

    # Export Module.symvers and header for dependent modules (FCI) and apps (dpa-app)
    install -d $out/include/cdx
    install -m 0644 Module.symvers $out/include/cdx/
    install -m 0644 cdx_ioctl.h $out/include/cdx/
    runHook postInstall
  '';

  meta = {
    description = "CDX (Control Data Exchange) kernel module for ASK fast path";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.gpl2Plus;
  };
}
