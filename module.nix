{
  config,
  lib,
  pkgs,
  ...
}:
let
  options.programs.companion = {
    package = lib.mkOption {
      type = lib.types.package;
      description = "Which companion package to install.";
    };
    enable = lib.mkEnableOption "Add Bitfocus Companion to installed packages.";
  };
  cfg = config.programs.companion;
in
{
  inherit options;
  config = lib.mkIf cfg.enable { environment.systemPackages = [ cfg.package ]; };
}
