# Power management for a machine with a battery and a lid. Imported by
# hosts/laptop only -- none of it means anything on a desktop.
{ pkgs, ... }:

{
  # s2idle on this chassis drains the battery overnight; deep suspend does not.
  boot.kernelParams = [ "mem_sleep_default=deep" ];

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Auto-switch power profile based on AC adapter state
  systemd.services.power-profile-ac = {
    description = "Set performance profile on AC power";
    script = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
    serviceConfig.Type = "oneshot";
  };

  systemd.services.power-profile-battery = {
    description = "Set power-saver profile on battery";
    script = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver";
    serviceConfig.Type = "oneshot";
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{online}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}="power-profile-ac.service"
    SUBSYSTEM=="power_supply", ATTR{online}=="0", TAG+="systemd", ENV{SYSTEMD_WANTS}="power-profile-battery.service"
  '';

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };

  #services.tlp = {
  #  enable = true;
  #  settings = {
  #    # Battery charging threshold 80%
  #    STOP_CHARGE_THRESH_BAT0 = 80;
  #  };
  #};
}
