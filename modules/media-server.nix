# Self-hosted media stack (the XDA "better than streaming" setup):
#
#   Seerr ──request──▶ Radarr / Sonarr ──search──▶ Prowlarr (indexers) ─▶ FlareSolverr (Cloudflare)
#                           │
#                           └──grab──▶ qBittorrent ──▶ /data/downloads
#                                                         │ (hardlink/move)
#   Jellyfin ◀──scans── /data/media/{movies,tv} ◀─────────┘
#   Bazarr adds subtitles next to the files Radarr/Sonarr manage.
#
# Every app is a pinned container run by Podman through
# virtualisation.oci-containers, which only writes the `podman run` into a
# systemd unit (podman-<name>.service): that is what starts them at boot and
# restarts them on failure, since Podman itself has no daemon to do either.
#
# Nothing in here is secret. The API keys the apps use to talk to each other
# are generated on first start and live under `${dataDir}/config`, on the
# machine, never in this repo.
#
# Enable on a host with `services.media-server.enable = true;`.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.media-server;

  # All apps share one network so they reach each other by container name
  # (http://radarr:7878, http://qbittorrent:8080, ...).
  network = "media";

  # One /data tree mounted identically into every app that touches files, so
  # a finished download moves into the library as an instant hardlink rather
  # than a copy -- the layout the Servarr wiki recommends.
  dataMount = "${cfg.dataDir}:/data";
  configMount = name: "${cfg.dataDir}/config/${name}:/config";

  linuxserverEnv = {
    PUID = toString cfg.uid;
    PGID = toString cfg.gid;
    TZ = config.time.timeZone or "UTC";
  };

  # Radarr/Sonarr/Prowlarr force a login since v5; `External` turns their own
  # auth off entirely (it's meant for "a proxy in front handles it"), which is
  # what we want for a LAN + tailnet-only box.
  servarrNoAuth = prefix: { "${prefix}__AUTH__METHOD" = "External"; };

  # qBittorrent rewrites qBittorrent.conf on exit, so these are enforced on
  # every start instead: whatever is changed in the web UI reverts to this on
  # the next restart.
  #
  # Seeding: stop a torrent the moment it finishes (ratio 0 / 0 minutes) --
  # "Stop", not "Remove", so Radarr/Sonarr still see it as completed and can
  # import it, then delete it themselves (their "Remove Completed" option).
  # Upload: BitTorrent can't download with zero upload, and 0 means
  # *unlimited* here, so 1 KiB/s is the lowest cap qBittorrent accepts.
  #
  # WebUI: no login from the LAN, the tailnet, or the containers' network.
  qbittorrentSettings = {
    BitTorrent = {
      "Session\\GlobalMaxRatio" = "0";
      "Session\\GlobalMaxSeedingMinutes" = "0";
      "Session\\GlobalMaxInactiveSeedingMinutes" = "0";
      "Session\\ShareLimitAction" = "Stop";
      "Session\\GlobalUPSpeedLimit" = toString cfg.qbittorrent.uploadLimitKiB;
      "Session\\AlternativeGlobalUPSpeedLimit" = toString cfg.qbittorrent.uploadLimitKiB;
      # Queue: how many torrents download at once (qBittorrent's default is
      # 3). MaxActiveTorrents caps downloads + seeds together, so it has to
      # be at least as high; finished torrents are stopped and don't count.
      # Stalled torrents (no peers) don't hold a slot either.
      "Session\\MaxActiveDownloads" = toString cfg.qbittorrent.maxActiveDownloads;
      "Session\\MaxActiveTorrents" = toString cfg.qbittorrent.maxActiveDownloads;
      "Session\\IgnoreSlowTorrentsForQueueing" = "true";
      "Session\\DefaultSavePath" = "/data/downloads";
      "Session\\TempPathEnabled" = "false";
    };
    WebUI = {
      Port = "8080";
      LocalHostAuth = "false";
      AuthSubnetWhitelistEnabled = "true";
      AuthSubnetWhitelist = "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10";
    };
  };

  qbittorrentConf = "${cfg.dataDir}/config/qbittorrent/qBittorrent/qBittorrent.conf";

  enforceQbittorrentSettings = pkgs.writeShellScript "qbittorrent-enforce-settings" ''
    set -eu
    mkdir -p "$(dirname ${qbittorrentConf})"
    touch ${qbittorrentConf}
    ${lib.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (section: keys:
      lib.mapAttrsToList (key: value:
        "${pkgs.crudini}/bin/crudini --ini-options=nospace --set ${qbittorrentConf} ${section} ${lib.escapeShellArg key} ${lib.escapeShellArg value}"
      ) keys
    ) qbittorrentSettings))}
    chown -R ${toString cfg.uid}:${toString cfg.gid} "$(dirname ${qbittorrentConf})"
  '';

  ports = {
    jellyfin = 8096;
    seerr = 5055;
    radarr = 7878;
    sonarr = 8989;
    bazarr = 6767;
    prowlarr = 9696;
    qbittorrent = 8080;
  };

  publish = name: [ "${toString ports.${name}}:${toString ports.${name}}" ];

  # Everything on the media network; flaresolverr is only reached by Prowlarr
  # from inside it (http://flaresolverr:8191), so it publishes no port.
  containerNames = lib.attrNames ports ++ [ "flaresolverr" ];
in
{
  options.services.media-server = {
    enable = lib.mkEnableOption "the Jellyfin/Seerr/*arr/qBittorrent media stack";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/media";
      description = "Root of the media library, downloads and every app's config.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "UID that owns the files (so they're also editable by hand).";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "GID that owns the files.";
    };

    nvidia = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pass the NVIDIA GPU to Jellyfin for hardware transcoding.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the web UI ports (LAN and tailnet).";
    };

    qbittorrent.uploadLimitKiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Global upload cap in KiB/s. 1 is the minimum; 0 would mean unlimited.";
    };

    qbittorrent.maxActiveDownloads = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Torrents downloading at the same time; the rest wait in the queue.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    hardware.nvidia-container-toolkit.enable = lib.mkIf cfg.nvidia true;

    systemd.tmpfiles.rules = map (dir: "d ${cfg.dataDir}/${dir} 0775 ${toString cfg.uid} ${toString cfg.gid} - -") [
      ""
      "downloads"
      "media"
      "media/movies"
      "media/tv"
      "config"
      "config/jellyfin"
      "config/seerr"
      "config/radarr"
      "config/sonarr"
      "config/bazarr"
      "config/prowlarr"
      "config/qbittorrent"
    ];

    systemd.services = lib.mkMerge [
      {
        podman-network-media = {
          description = "Podman network for the media stack";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ config.virtualisation.podman.package ];
          script = "podman network exists ${network} || podman network create ${network}";
        };

        # Merged with the oci-containers unit, so its own pre-start still runs first.
        podman-qbittorrent.serviceConfig.ExecStartPre = [ "${enforceQbittorrentSettings}" ];
      }
      (lib.genAttrs (map (n: "podman-${n}") containerNames) (_: {
        requires = [ "podman-network-media.service" ];
        after = [ "podman-network-media.service" ];
      }))
    ];

    virtualisation.oci-containers.containers = {
      jellyfin = {
        image = "lscr.io/linuxserver/jellyfin:10.11.11ubu2604-ls47";
        environment = linuxserverEnv;
        volumes = [ (configMount "jellyfin") dataMount ];
        ports = publish "jellyfin";
        networks = [ network ];
        devices = lib.optional cfg.nvidia "nvidia.com/gpu=all";
      };

      seerr = {
        image = "ghcr.io/seerr-team/seerr:v3.5.1";
        environment = { TZ = linuxserverEnv.TZ; PORT = toString ports.seerr; };
        # Seerr runs as its built-in UID 1000 rather than honouring PUID.
        volumes = [ "${cfg.dataDir}/config/seerr:/app/config" ];
        ports = publish "seerr";
        networks = [ network ];
        extraOptions = [ "--init" ];
      };

      radarr = {
        image = "lscr.io/linuxserver/radarr:6.4.4.10685-ls324";
        environment = linuxserverEnv // servarrNoAuth "RADARR";
        volumes = [ (configMount "radarr") dataMount ];
        ports = publish "radarr";
        networks = [ network ];
      };

      sonarr = {
        image = "lscr.io/linuxserver/sonarr:4.0.20.3014-ls329";
        environment = linuxserverEnv // servarrNoAuth "SONARR";
        volumes = [ (configMount "sonarr") dataMount ];
        ports = publish "sonarr";
        networks = [ network ];
      };

      bazarr = {
        image = "lscr.io/linuxserver/bazarr:v1.6.2-ls370";
        environment = linuxserverEnv;
        volumes = [ (configMount "bazarr") dataMount ];
        ports = publish "bazarr";
        networks = [ network ];
      };

      prowlarr = {
        image = "lscr.io/linuxserver/prowlarr:2.7.0.5723-ls166";
        environment = linuxserverEnv // servarrNoAuth "PROWLARR";
        volumes = [ (configMount "prowlarr") ];
        ports = publish "prowlarr";
        networks = [ network ];
      };

      # Headless browser that solves Cloudflare challenges for the indexers
      # Prowlarr routes through it (those tagged to use the FlareSolverr proxy).
      flaresolverr = {
        image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2";
        environment = { TZ = linuxserverEnv.TZ; LOG_LEVEL = "info"; };
        networks = [ network ];
      };

      qbittorrent = {
        image = "lscr.io/linuxserver/qbittorrent:5.3.0_v2.1.2-ls485";
        environment = linuxserverEnv // { WEBUI_PORT = toString ports.qbittorrent; };
        volumes = [ (configMount "qbittorrent") dataMount ];
        ports = publish "qbittorrent";
        networks = [ network ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall (lib.attrValues ports);
  };
}
