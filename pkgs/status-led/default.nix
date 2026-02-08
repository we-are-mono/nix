{ lib, stdenv }:

stdenv.mkDerivation {
  pname = "status-led";
  version = "1.0";

  src = ./status-led.sh;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/status-led.sh
    runHook postInstall
  '';

  meta = {
    description = "Status LED control for boot and online states";
    platforms = [ "aarch64-linux" ];
    license = lib.licenses.mit;
  };
}
