{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    supportedSystems =
      nixpkgs.lib.attrsets.getAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ]
      nixpkgs.legacyPackages;
  in {
    overlays.default = (
      final: prev: {
        # TODO: prev or final here? nixpkgs manual says use prev for fns?
        # "flakes arn't real" uses final...
        companion = prev.callPackage ./companion.nix {};
      }
    );

    packages =
      builtins.mapAttrs (
        system: pkgs: let
          # https://jade.fyi/blog/flakes-arent-real/
          companion = (self.overlays.default pkgs pkgs).companion;
        in {
          nodejs = companion.nodejs;
          yarn1 = companion.yarn1;
          yarn-berry = companion.yarn-berry;
          companion = companion;
          default = companion;
        }
      )
      supportedSystems;

    nixosModules.default = {
      pkgs,
      config,
      lib,
      ...
    }: {
      imports = [./module.nix];
      # inject flake deps into module via overlay
      config = lib.mkIf config.programs.companion.enable {
        nixpkgs.overlays = [self.overlays.default];
        programs.companion.package = lib.mkDefault pkgs.companion;
      };
    };

    # devShell to facilitate manual builds and experiments.
    devShells =
      builtins.mapAttrs (system: pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.neovim
            pkgs.nixfmt-rfc-style
          ];
        };
      })
      supportedSystems;
    nixosConfigurations.testos = let
      system = "x86_64-linux";
    in
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            imports = [self.nixosModules.default];
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

            # Add a non-root user for testing the service
            users.users.test = {
              isNormalUser = true;
              initialPassword = "password";
              group = "users";
            };

            # Enable companion with service configuration
            programs.companion = {
              enable = true;
              autoStart = true;
              user = "test"; # Use the test user we created
              openFirewall = true;
            };

            # Enable SSH for easier access to the VM
            services.openssh.enable = true;
            services.openssh.settings.PermitRootLogin = "yes";
            networking.firewall.allowedTCPPorts = [22];
          }
        ];
      };
  };
}
