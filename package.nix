# Adapted from upstream: https://github.com/Tiebe/nixpkgs/blob/cd08eb2bba056f9bf8f047423919d763a91f87cc/pkgs/by-name/bi/bitfocus-companion/package.nix
# from https://github.com/NixOS/nixpkgs/pull/418848
{
  stdenv,
  lib,
  fetchFromGitHub,
  nodejs,
  git,
  python3,
  udev,
  yarn-berry_4,
  libusb1,
  iputils,
  dart-sass,
  makeWrapper,
  nix-update-script,
}: let
  yarn-berry = yarn-berry_4;

  selectSystem = attrs:
    attrs.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
  platform = selectSystem {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    armv7l-linux = "linux-armv7l";
  };
in
  stdenv.mkDerivation rec {
    pname = "bitfocus-companion";
    version = "4.1.4";

    strictDeps = true;

    src = fetchFromGitHub {
      owner = "bitfocus";
      repo = "companion";
      tag = "v${version}";
      hash = "sha256-4l28vgMo/hy8lgMd69MLxBmI41sgNGDYnKUZafZDT5k=";
    };

    passthru.updateScript = nix-update-script {};

    postPatch = ''
      # patch out git calls to generate version strings.
      substituteInPlace tools/lib.mts --replace-fail "return await fcn()" "return \"v${version}\""

      # remove the yarn install during the build, since there is no internet connection, and everything has already been installed by yarnBerryConfigHook
      substituteInPlace tools/build/dist.mts \
        --replace-fail 'await $`yarn --cwd node_modules/better-sqlite3 prebuild-install --arch=''${platformInfo.nodeArch}`' "" \
        --replace-fail 'await $`yarn workspace @companion-app/launcher-ui build`' ""

      substituteInPlace tools/build/package.mts --replace-fail "await $\`yarn install --no-immutable\`" ""

      # remove node download, since we'll use the nix version
      substituteInPlace tools/build/package.mts \
        --replace-fail "const nodeVersions = await fetchNodejs(platformInfo)" "const nodeVersions = []" \
        --replace-fail "await fs.createSymlink(latestRuntimeDir, path.join(runtimesDir, 'main'))" ""

      substituteInPlace companion/lib/Instance/NodePath.ts \
        --replace-fail "if (!(await fs.pathExists(nodePath))) return null" "return '${lib.getExe nodejs}'" \
    '';

    nativeBuildInputs = [
      nodejs
      yarn-berry.yarnBerryConfigHook
      git
      python3
      yarn-berry
      makeWrapper
    ];

    buildInputs = [
      libusb1
      dart-sass
      nodejs
      udev
    ];

    missingHashes = ./missing-hashes.json;

    offlineCache = yarn-berry.fetchYarnBerryDeps {
      inherit src missingHashes;
      hash = "sha256-bOqUIizc6WClJUWhYVekqbru+FrHmDAMVpbrpVTkgeU=";
    };

    env = {
      ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
      SKIP_LAUNCH_CHECK = true;
      ELECTRON = 0;
    };

    # with dontConfigure it doesn't seem to retrieve node_modules, so empty configurePhase instead
    configurePhase = ''
      runHook preConfigure
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild

      # force sass-embedded to use our own sass instead of the bundled one
      substituteInPlace node_modules/sass-embedded/dist/lib/src/compiler-path.js \
          --replace-fail 'compilerCommand = (() => {' 'compilerCommand = (() => { return ["${lib.getExe dart-sass}"];'

      yarn dist ${platform}

      runHook postBuild
    '';

    preInstall = ''
      # remove node runtime, since we will always use the nix node runtime
      rm -rf .cache/node-runtimes
      rm -rf dist/node-runtimes
      rm -rf node_modules/app-builder-bin
    '';

    installPhase = ''
      runHook preInstall

      # setup udev rules
      install -Dm644 assets/linux/50-companion-desktop.rules -t $out/etc/udev/rules.d/

      mkdir -p $out/share/bitfocus-companion
      cp -r * $out/share/bitfocus-companion/

      # Upstream docker includes udev at both build and runtime
      # Upstream docker includes iputils at runtime
      makeWrapper ${lib.getExe nodejs} $out/bin/bitfocus-companion \
        --add-flags $out/share/bitfocus-companion/dist/main.js \
        --set LD_LIBRARY_PATH "${lib.makeLibraryPath [libusb1 udev]}" \
        --set NODE_PATH $out/share/bitfocus-companion/node_modules \
        --suffix PATH : "${lib.makeBinPath [iputils]}"

      runHook postInstall
    '';

    meta = {
      description = "Program for controlling Stream Deck devices";
      longDescription = "Bitfocus Companion enables the Elgato Stream Deck and other controllers to be a professional shotbox surface for an increasing amount of different presentation switchers, video playback software and broadcast equipment.";
      homepage = "https://bitfocus.io/companion";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [tiebe];
      mainProgram = "bitfocus-companion";
      platforms = lib.platforms.linux;
    };
  }
