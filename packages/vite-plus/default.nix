{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "vite-plus";
  version = "0.2.9";

  src = fetchurl {
    url = "https://github.com/voidzero-dev/vite-plus/releases/download/v${finalAttrs.version}/vp-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-UcZtrEPy51Dc6a1RLMPnAI3T0aMwTdmYGN6gG9OLl74=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    tar -xzf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 vp "$out/bin/vp"
    runHook postInstall
  '';

  meta = {
    description = "Unified toolchain for the web";
    homepage = "https://viteplus.dev";
    license = lib.licenses.mit;
    mainProgram = "vp";
    platforms = [ "x86_64-linux" ];
  };
})
