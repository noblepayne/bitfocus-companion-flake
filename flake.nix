{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      supportedSystems = {
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin;
        aarch64-linux = nixpkgs.legacyPackages.aarch64-linux;
        x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin;
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux;
      };
    in
    {

      packages = builtins.mapAttrs (
        system: pkgs:
        let
          companion = pkgs.callPackage ./companion.nix { };
        in
        {
          nodejs = companion.nodejs;
          yarn1 = companion.yarn1;
          yarn-berry = companion.yarn-berry;
          companion = companion;
          default = companion;
        }
      ) supportedSystems;
      # Set companion launcher script as main output for `nix build`.
      # default = self.packages.${system}.companion;

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
              environment.systemPackages = [ self.packages.${system}.companion ];
            }
          ];
        };
    };
}
