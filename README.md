# Bitfocus Companion Flake

A NixOS flake for [Bitfocus Companion](https://bitfocus.io/companion).

## Quick Start
```bash
nix run github:noblepayne/bitfocus-companion-flake
```

Or add to your NixOS configuration:
```nix
{
  inputs.companion.url = "github:noblepayne/bitfocus-companion-flake";
  
  outputs = { self, nixpkgs, companion, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        companion.nixosModules.default
        {
          programs.companion.enable = true;
          programs.companion.runAsService = true;
          programs.companion.user = "companion";
          programs.companion.group = "companion";
        }
      ];
    };
  };
}
```

## Updating dependencies

When Companion updates, regenerate `missing-hashes.json`:
```bash
./update-missing-hashes.sh
```

This uses `yarn-berry-fetcher` to compute the integrity hashes for all yarn dependencies from the new `yarn.lock`.

## License

MIT

## Related

An upstream nixpkgs package is in progress: https://github.com/NixOS/nixpkgs/pull/418848
