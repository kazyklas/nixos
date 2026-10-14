# opencode, built from the upstream prebuilt release binary.
#
# The nixpkgs source build of opencode 1.18.30 is broken: its bundled JS ends up
# with an `undefined` entry in the dependency list of the internal service-layer
# graph, so every prompt dies in SystemPrompt.environment with
# "TypeError: undefined is not an object (evaluating 'a.name')" and the TUI shows
# "Failed to send prompt". The upstream binary of the same version is fine.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, makeWrapper
, ripgrep
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "1.18.30";

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${finalAttrs.version}/opencode-linux-x64.tar.gz";
    hash = "sha256-VQByRoWBZUlv+FuhwrZI90IejiATv0GJpoDJ/45pnRc=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/opencode \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]} \
      --set-default OPENCODE_DISABLE_AUTOUPDATE true
  '';

  meta = {
    description = "AI coding agent built for the terminal (upstream prebuilt binary)";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
