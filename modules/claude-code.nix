{ ... }:

{
  # Claude Code's config dir (~/.claude) is generated from modules/claude/.
  # Only the entries declared here are managed, so settings.json and the rest
  # of ~/.claude stay mutable -- deliberately: Claude Code writes to
  # settings.json itself (/config, /model, remembered permissions), and
  # managing it here would turn it into a read-only store symlink.
  programs.claude-code = {
    enable = true;

    # A path rather than an attribute set: home-manager readDirs it, so adding
    # a skill is "create a folder with a SKILL.md" with no change to this file.
    # Note that the flake only sees git-tracked files, so a new skill has to be
    # `git add`ed before it shows up.
    skills = ./claude/skills;
  };
}
