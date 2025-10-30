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
    runAsService = lib.mkEnableOption "Run Companion as a systemd service instead of just installing the package.";
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start Bitfocus Companion automatically at boot (only used when runAsService is enabled).";
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = "User under which the Companion service will run (required when runAsService is enabled).";
    };
    group = lib.mkOption {
      type = lib.types.str;
      description = "Group under which the Companion service will run (required when runAsService is enabled).";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open firewall ports for Companion (only used when runAsService is enabled).";
    };
  };
  cfg = config.programs.companion;
in {
  inherit options;
  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.mkIf (!cfg.runAsService) [cfg.package];
    systemd.services.companion = lib.mkIf cfg.runAsService {
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
    networking.firewall = lib.mkIf (cfg.runAsService && cfg.openFirewall) {
      allowedTCPPorts = [8000];
    };
  };
}
