{
  config,
  lib,
  pkgs,
  ...
}: let
  options.programs.companion = {
    package = lib.mkOption {
      type = lib.types.package;
      description = "Which companion package to install.";
    };
    enable = lib.mkEnableOption "Add Bitfocus Companion to installed packages.";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start Bitfocus Companion automatically at boot.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "stripe";
      description = "User under which the Companion service will run.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group under which the Companion service will run.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open firewall ports for Companion.";
    };
  };
  cfg = config.programs.companion;
in {
  inherit options;

  config = lib.mkIf cfg.enable {
    # Install the package
    environment.systemPackages = [cfg.package];

    # Create a systemd service
    systemd.services.companion = {
      description = "Bitfocus Companion";
      wantedBy = lib.mkIf cfg.autoStart ["multi-user.target"];
      after = ["network.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/companion";
        Restart = "on-failure";
        RestartSec = "10s";
        NoNewPrivileges = true;
        ProtectSystem = "full";
        ProtectHome = lib.mkDefault false;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [8000];
    };
  };
}
