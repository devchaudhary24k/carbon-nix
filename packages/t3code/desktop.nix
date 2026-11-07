# T3 Code's desktop app, from the official AppImage. Same version as the
# server package; both read sources.json.
#
# The app runs its own local server, so it works on its own, and it can also
# connect to the server on carbon over the tailnet.
{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
}:

let
  sources = lib.importJSON ./sources.json;
  pname = "t3code-desktop";
  inherit (sources) version;

  src = fetchurl { inherit (sources.desktop) url hash; };
  contents = appimageTools.extract { inherit pname version src; };
in

appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    # Native Wayland instead of XWayland, and working input methods.
    wrapProgram $out/bin/${pname} \
      --add-flags "--ozone-platform-hint=auto --enable-wayland-ime"

    install -Dm444 ${contents}/t3code.desktop $out/share/applications/t3code.desktop
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${contents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "Desktop app for coding agents";
    homepage = "https://t3.codes";
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
