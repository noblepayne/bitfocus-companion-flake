{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      supportedSystems = nixpkgs.lib.attrsets.getAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ] nixpkgs.legacyPackages;
    in
    {
      overlays.default = (
        final: prev: {
          # TODO: prev or final here? nixpkgs manual says use prev for fns?
          # "flakes arn't real" uses final...
          companion = prev.callPackage ./companion.nix { };
        }
      );

      packages = builtins.mapAttrs (
        system: pkgs:
        let
          # https://jade.fyi/blog/flakes-arent-real/
          companion = (self.overlays.default pkgs pkgs).companion;
        in
        {
          nodejs = companion.nodejs;
          yarn1 = companion.yarn1;
          yarn-berry = companion.yarn-berry;
          companion = companion;
          default = companion;
        }
      ) supportedSystems;

      nixosModules.default =
        {
          pkgs,
          config,
          lib,
          ...
        }:
        {
          imports = [ ./module.nix ];
          # inject flake deps into module via overlay
          config = lib.mkIf config.programs.companion.enable {
            nixpkgs.overlays = [ self.overlays.default ];
            programs.companion.package = lib.mkDefault pkgs.companion;
          };
        };

      # devShell to facilitate manual builds and experiments.
      devShells = builtins.mapAttrs (system: pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.neovim
            pkgs.nixfmt-rfc-style
            # pkgs.libusb
            # pkgs.fontconfig
            # pkgs.udev
            # self.packages.${system}.nodejs
            # self.packages.${system}.yarn-berry
          ];
          # LD_LIBRARY_PATH = "${nixpkgs.lib.makeLibraryPath [
          #   pkgs.libusb
          #   pkgs.fontconfig
          #   pkgs.udev
          # ]}";
        };
      }) supportedSystems;

      nixosConfigurations.testos =
        let
          system = "x86_64-linux";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            {
              imports = [ self.nixosModules.default ];
              boot.loader.grub.device = "nodev";
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
                options = [
                  "defaults"
                  "mode=755"
                ];
              };
              users.users.root.initialPassword = "password";
              programs.companion.enable = true;
            }
          ];
        };
    };
}
