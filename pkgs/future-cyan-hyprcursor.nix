# Future Cyan, a Hyprcursor theme ported from the Future-cursor Xcursor theme
# (itself derived from capitaine-cursors). Not in nixpkgs, so it's vendored
# here from its GitLab repo -- there are no tags, so this pins the latest
# commit on `main` as of writing.
#
# modules/hyprland.nix already points HYPRCURSOR_THEME at
# "Future-Cyan-Hyprcursor_Theme"; this package is what actually puts a theme
# of that name where Hyprcursor (and anything else following the XDG icon
# theme spec) looks for it -- $out/share/icons ends up on $XDG_DATA_DIRS via
# the Home Manager profile.
{ lib, stdenvNoCC, fetchFromGitLab }:

stdenvNoCC.mkDerivation {
  pname = "future-cyan-hyprcursor";
  version = "unstable-2025-10-05";

  src = fetchFromGitLab {
    owner = "Pummelfisch";
    repo = "future-cyan-hyprcursor";
    rev = "cf4126d17f4520aceb688d8a60daca4a1f0b9e80";
    hash = "sha256-a7LdP2VH0UlMPwW9vbBolOuPQMJa0WNpmJfLLv3JZ4g=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/icons"
    cp -r Future-Cyan-Hyprcursor_Theme "$out/share/icons/"
    runHook postInstall
  '';

  meta = {
    description = "Futuristic Hyprcursor theme (dark, cyan accents), ported from the Future-cursor Xcursor theme";
    homepage = "https://gitlab.com/Pummelfisch/future-cyan-hyprcursor";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
  };
}
