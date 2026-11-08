# T3 Code's server and CLI (`t3`), repackaged from the official Linux release.
#
# nixpkgs carries a source build that lags far behind upstream (0.0.24 when
# this was written), so this takes the prebuilt tarball instead and patches its
# binaries to find their libraries in the Nix store. Bump it with
# ./update.sh, which rewrites sources.json.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libgcc,
  vulkan-loader,
}:

let
  sources = lib.importJSON ./sources.json;
in

stdenv.mkDerivation {
  pname = "t3code";
  inherit (sources) version;

  src = fetchurl { inherit (sources.server) url hash; };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    stdenv.cc.cc.lib
    libgcc
    # Voice transcription's GPU backend.
    vulkan-loader
  ];

  # The bundle ships optional native modules for musl as well as glibc. Only
  # the glibc ones are ever loaded here.
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

  # `t3` is a single-file executable with its JavaScript appended after the
  # ELF image. Stripping would cut that payload off.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/t3 $out/bin
    cp -r . $out/lib/t3/
    # A symlink rather than a wrapper script, so the binary still finds its
    # client/ and node_modules/ next to its real path.
    ln -s $out/lib/t3/t3 $out/bin/t3
    runHook postInstall
  '';

  passthru.sources = sources;

  meta = {
    description = "Web GUI for coding agents (server and CLI)";
    homepage = "https://t3.codes";
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
