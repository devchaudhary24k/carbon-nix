# Minecraft Console Client, a headless Minecraft client.
#
# Upstream ships one self-contained .NET single-file bundle per platform rather
# than a tarball, so there is nothing to unpack and nothing to compile.
#
# Do not add autoPatchelfHook. A single-file bundle stores byte offsets to its
# embedded payload in a footer, and rewriting the ELF shifts them, after which
# the binary dies with "Arithmetic overflow while reading bundle". The
# interpreter it asks for, /lib64/ld-linux-x86-64.so.2, is instead supplied by
# programs.nix-ld; modules/mcc.nix asserts that is enabled.
#
# LD_LIBRARY_PATH is still needed because the bundle unpacks its native
# libraries to a temporary directory at runtime, and nothing rewrites those.
{
  curl,
  fetchurl,
  icu,
  krb5,
  lib,
  libunwind,
  makeWrapper,
  openssl,
  stdenv,
  zlib,
  zstd,
}:

let
  runtimeLibraries = [
    curl
    icu
    krb5
    libunwind
    openssl
    stdenv.cc.cc
    zlib
    zstd
  ];
in

stdenv.mkDerivation (finalAttrs: {
  pname = "minecraft-console-client";
  version = "20260906-516";

  src = fetchurl {
    url = "https://github.com/MCCTeam/Minecraft-Console-Client/releases/download/${finalAttrs.version}/MinecraftClient-${finalAttrs.version}-linux-x64";
    hash = "sha256-0126tQ23pIYWuRJaI8+KJq3eznXiKDwwRJnuZz2m7aY=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/libexec/MinecraftClient"
    makeWrapper "$out/libexec/MinecraftClient" "$out/bin/MinecraftClient" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries}
    runHook postInstall
  '';

  # The libraries the wrapper injects, so a module can hand the same set to
  # programs.nix-ld without repeating the list.
  passthru.runtimeLibraries = runtimeLibraries;

  meta = {
    description = "Headless Minecraft client and bot framework";
    homepage = "https://mccteam.github.io/";
    license = lib.licenses.cc0;
    mainProgram = "MinecraftClient";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
