{
  # builders and fetchers
  stdenv,
  fetchurl,
  fetchFromGitHub,
  # yarn builds
  fetchYarnDeps,
  fixup-yarn-lock,
  yarn,
  cacert,
  python3,
  git,
  nodejs_18,
  yarn-berry,
  # runtime deps
  libusb,
  udev,
  fontconfig,
  patchelf,
  autoPatchelfHook,
  # script deps
  writeShellApplication,
  xdg-utils,
  makeDesktopItem,
  ...
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "companion";
  version = "v3.3.1";

  # Fetch v3.3.0 of Bitfocus Companion.
  companionRepo = fetchFromGitHub {
    owner = "bitfocus";
    repo = "companion";
    rev = finalAttrs.version;
    hash = "sha256-Pb2WJvHixa3SIrtrP3h+MLCVzj6Unl7ZbsUn5MV8HnQ=";
    # Bundled companion modules are shipped as submodule, so fetch.
    fetchSubmodules = true;
  };

  # Fetch yarn v1 deps for module-legacy.
  legacyOfflineCache = fetchYarnDeps {
    yarnLock = "${finalAttrs.companionRepo}/module-legacy/yarn.lock";
    hash = "sha256-qJtpLzXqEzVQwQkVmQRtTdMLioQUrbtWD1lpe4YdVdI= ";
  };

  # We need several different versions of typescript to compile some legacy bitfocus modules
  # that do not ship pre-compiled outputs.
  # TODO: Do we need all these versions?
  # TODO: Use fetchYarnDeps and fetchFromGithub (and build the node packages) instead of hardcoding tsc versions?
  typescript423 = fetchurl {
    url = "https://registry.yarnpkg.com/typescript/-/typescript-4.2.3.tgz";
    hash = "sha256-z1jvV6ixc/rZ+Blp05lSmeQMdwoCgFEXUgtMddQ/8Uo=";
  };
  typescript455 = fetchurl {
    url = "https://registry.yarnpkg.com/typescript/-/typescript-4.5.5.tgz";
    hash = "sha256-nsR5Zy5I2fS3LBodzbWvBj7OfCdPOpMtlrmsxg0QD+g=";
  };
  typescript483 = fetchurl {
    url = "https://registry.yarnpkg.com/typescript/-/typescript-4.8.3.tgz";
    hash = "sha256-7NqTzi0jBfnOcwp43mokhum3f77Anw51oBu0P9wcldk=";
  };

  # Patch node to use libusb-1.0, libudev, and libfontconfig which are dynamically
  # dlopened by companion at runtime.
  nodejs = stdenv.mkDerivation {
    pname = "nodejs-with-libs";
    version = nodejs_18.version;
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = nodejs_18.buildInputs ++ [
      libusb
      fontconfig
      udev
      patchelf
    ];
    src = nodejs_18;
    buildPhase = ''
      # Copy all files from pkgs.nodejs_18 to our output.
      mkdir $out
      cp -r * $out
    '';
    installPhase = ''
      # Add additional library dependencies to node binary.
      patchelf --add-needed libusb-1.0.so \
               --add-needed libfontconfig.so \
               --add-needed libudev.so \
               $out/bin/node
    '';
  };

  yarn1 = yarn.override { nodejs = finalAttrs.nodejs; };
  yarn-berry = yarn-berry.override { nodejs = finalAttrs.nodejs; };

  # Build module-legacy.
  moduleLegacy = stdenv.mkDerivation {
    pname = "module-legacy";
    version = finalAttrs.version;
    src = "${finalAttrs.companionRepo}/module-legacy";
    nativeBuildInputs = [
      finalAttrs.nodejs
      finalAttrs.yarn1
      fixup-yarn-lock
    ];
    buildPhase = ''
      # Setup yarn to use our pre-fetched deps as an offline cache.
      export HOME=$(mktemp -d)
      yarn config --offline set yarn-offline-mirror ${finalAttrs.legacyOfflineCache}
      # TODO: shouldn't be needed, but is it safer to just use the lock from the cache vs from the repo?
      cp "${finalAttrs.legacyOfflineCache}/yarn.lock" .
      # TODO: needed? get better understanding of what fixups this applies.
      fixup-yarn-lock yarn.lock
      # Install pre-fetched deps into node_modules.
      yarn install --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive
      # Patch shebangs so binaries/scripts in node_modules will run under nix.
      patchShebangs node_modules

      # Manually compile deps that don't include prebuilt outputs.

      # linkbox-remote
      PKGTMP=$(mktemp -d)  # temporary dir to store installed typescript version.
      pushd $PKGTMP
      npm install --install-strategy=shallow ${finalAttrs.typescript423}  # install typescript tarball.
      patchShebangs node_modules  # fixup tsc script for nix env.
      popd
      pushd node_modules/companion-module-linkbox-remote
      $PKGTMP/node_modules/.bin/tsc -p tsconfig.build.json  # compile!
      popd

      # magewell-ultrastream
      PKGTMP=$(mktemp -d)
      pushd $PKGTMP
      npm install --install-strategy=shallow ${finalAttrs.typescript483}
      patchShebangs node_modules
      popd
      pushd node_modules/companion-module-magewell-ultrastream
      $PKGTMP/node_modules/.bin/tsc -p tsconfig.build.json
      popd

      # olzzon-ndicontroller
      PKGTMP=$(mktemp -d)
      pushd $PKGTMP
      npm install --install-strategy=shallow ${finalAttrs.typescript455}
      patchShebangs node_modules
      popd
      pushd node_modules/companion-module-olzzon-ndicontroller
      $PKGTMP/node_modules/.bin/tsc -p tsconfig.build.json
      popd

      # These last two both reuse typescript 4.5.5 so we can skip installation/setup.

      # seervision-suite
      pushd node_modules/companion-module-seervision-suite
      $PKGTMP/node_modules/.bin/tsc -p tsconfig.build.json
      popd

      # videocom-zoom-bridge
      pushd node_modules/companion-module-videocom-zoom-bridge
      $PKGTMP/node_modules/.bin/tsc -p tsconfig.build.json
      popd

      # Build module-legacy.
      yarn run --offline generate-manifests

      # Copy built outputs to the nix store.
      mkdir $out
      cp -r dist $out
      cp -r entrypoints $out
      cp -r manifests $out
    '';
  };

  # Fetch deps for main companion package.
  companionOfflineCache = stdenv.mkDerivation {
    pname = "companion-offline-cache";
    version = finalAttrs.version;
    src = finalAttrs.companionRepo;
    dontConfigure = true;
    nativeBuildInputs = [
      finalAttrs.yarn-berry
      cacert
      python3
      git
    ];
    buildPhase = ''
      # Setup env for yarn.
      export SSL_CERT_FILE="${cacert}/etc/ssl/ca-certificates.conf"
      export HOME=$(mktemp -d)
      git config --global user.name "builder"
      git config --global user.email "builder@nix.example.com"
      git init
      git add *
      git commit -m "init"

      # Setup yarn offline cache.
      mkdir yarnCache
      export YARN_ENABLE_GLOBAL_CACHE=false
      export YARN_CACHE_FOLDER=$PWD/yarnCache

      # Run yarn to pull all deps.
      yarn --immutable

      # Save cached files to nix store.
      mkdir -p $out/yarnCache
      mkdir -p $out/homeCache
      cp -r yarnCache/* $out/yarnCache/
      cp -r $HOME/.cache/* $out/homeCache/
    '';
    # use a fixed output derivation to allow yarn network access to prefetch deps.
    outputHashAlgo = "sha256";
    outputHash = "sha256-tcf+Bsvdl3o0jQ9L0pIJ+CG/uvcZs3sdJmJqYkOoGfU=";
    outputHashMode = "recursive";
  };

  # Manually prefech node-pre-gyp file for @julusian/skia-canvas.
  skiaCanvasVersion = "v1.0.5";
  skia-canvas =
    let
      buildPlatform = stdenv.buildPlatform;
      os = if buildPlatform.isDarwin then "darwin" else "linux";
      arch = if buildPlatform.efiArch != "aa64" then buildPlatform.efiArch else "arm64";
      # TODO: support musl/"unknown" with linux?
      libc = if buildPlatform.isDarwin then "unknown" else "glibc";
      # TODO: don't hardcode napi version?
      artifactId = "${os}-${arch}-napi-v6-${libc}";
      hashes = {
        linux-x64-napi-v6-glibc = "sha256-PnXokx3G3oszim+V/QFkEbDtCGF4DdbsSlDI4Z0fmL8=";
        linux-arm64-napi-v6-glibc = "sha256-yEyfska9rVdbNDSQWZZZl6h4MCewdA/g18yyv0juQgM=";
        darwin-x64-napi-v6-unknown = "sha256-56KkYMJNYhyLXjchNP597eCY2h+Rl4bOyBIWADFopXc=";
        darwin-arm64-napi-v6-unknown = "sha256-Kn1eVd7q6uidA5Gx5RCivlZH3F8zNb7//vkXRxl2Y1o=";
      };
      hash = hashes.${artifactId};
      artifact = "${artifactId}.tar.gz";
      url = "https://github.com/Julusian/skia-canvas/releases/download/${finalAttrs.skiaCanvasVersion}/${artifact}";
      tar = fetchurl {
        inherit url;
        inherit hash;
      };
    in
    stdenv.mkDerivation {
      pname = "skia-canvas";
      version = finalAttrs.skiaCanvasVersion;
      src = tar;
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/${finalAttrs.skiaCanvasVersion}
        cp ${tar} $out/${finalAttrs.skiaCanvasVersion}/${artifact}
        runHook postInstall
      '';
    };

  # Manually prefech node-pre-gyp file for @julusian/skia-canvas.
  # skia-canvas-node-pre-gyp = pkgs.fetchurl {
  #   url = "https://github.com/Julusian/skia-canvas/releases/download/v1.0.5/linux-x64-napi-v6-glibc.tar.gz";
  #   hash = "sha256-PnXokx3G3oszim+V/QFkEbDtCGF4DdbsSlDI4Z0fmL8=";
  # };

  # Build companion package (including all yarn workspaces).
  companionPkg = stdenv.mkDerivation {
    pname = "companion-pkg";
    version = finalAttrs.version;
    src = finalAttrs.companionRepo;
    dontConfigure = true;
    nativeBuildInputs = [
      finalAttrs.companionOfflineCache
      finalAttrs.yarn-berry
      finalAttrs.nodejs
      cacert
      python3
      git
    ];
    # Add back support for emojis that was disabled due to problems on windows...
    patches = [ ./add-emoji-support.patch ];
    buildPhase = ''
      # Setup env for yarn.
      export SSL_CERT_FILE="${cacert}/etc/ssl/ca-certificates.conf"
      export HOME=$(mktemp -d)
      git config --global user.name "builder"
      git config --global user.email "builder@nix.example.com"
      git init
      git add *
      git commit -m "init"

      # Restore offline cache files so we don't need network access.
      mkdir yarnCache
      export YARN_ENABLE_GLOBAL_CACHE=false
      export YARN_CACHE_FOLDER=$PWD/yarnCache
      cp -r ${finalAttrs.companionOfflineCache}/yarnCache/* yarnCache/
      mkdir $HOME/.cache
      cp -r ${finalAttrs.companionOfflineCache}/homeCache/* $HOME/.cache/

      # Configure yarn to operate offline using our prefetched files.
      export YARN_ENABLE_OFFLINE_MODE=1
      export YARN_ENABLE_NETWORK=false

      # Configure node-pre-gyp to build from source.
      # export npm_config_build_from_source=true  # doesn't work due to no node-gyp support in project.
      # Configure node-pre-gyp to use our precached files.
      # TARTMP=$(mktemp -d)
      # mkdir "$TARTMP/v1.0.5"
      # TODO: move to derivation? less janky handling of name and version?
      # cp "${finalAttrs.skia-canvas}" \
      #    "$TARTMP/v1.0.5/linux-x64-napi-v6-glibc.tar.gz"
      # magic yarn env var to pass options to node-pre-gyp to use offline cache
      export npm_config_index_binary_host_mirror="file://${finalAttrs.skia-canvas}"

      # Install prefetched deps (into node_modules).
      yarn --immutable
      patchShebangs node_modules  # allow scripts/bins to run in nix env.

      # Add prebuilt module-legacy files into our build environment.
      cp -r "${finalAttrs.moduleLegacy}"/* module-legacy/

      # Manually run selected build commands from full project build.
      export PATH="$PWD/node_modules/.bin:$PATH"  # add node_modules binaries to path.
      zx tools/build/dist.mjs  # build project (skipping package.mjs, so not running complete.mjs)
      pushd dist
      yarn --no-immutable  # install final set of deps needed for built project.
      popd

      # Copy built package to nix store.
      mkdir $out
      cp -r dist/* $out
    '';
  };

  # Finally, create a shellscript to use our custom node to run main.js from our pre-compiled
  # companion package output.
  companionBin = writeShellApplication {
    name = "companionBin";
    runtimeInputs = [ finalAttrs.nodejs ];
    text = ''
      (sleep 1 && ${xdg-utils}/bin/xdg-open "http://localhost:8000") &
      node ${finalAttrs.companionPkg}/main.js
    '';
  };

  companionDesktopIcon = ./bitfocusCompanion.png;

  companionDesktop = makeDesktopItem {
    name = "bitfocusCompanion";
    desktopName = "Bitfocus Companion";
    exec = "${finalAttrs.companionBin}/bin/companionBin";
    icon = "bitfocusCompanion";
    categories = [ "AudioVideo" ];
    terminal = true;
  };

  buildCommand = ''
    mkdir -p $out/bin
    cp "${finalAttrs.companionBin}/bin/companionBin" "$out/bin/companion"
    mkdir -p $out/share/applications
    cp "${finalAttrs.companionDesktop}/share/applications/bitfocusCompanion.desktop" "$out/share/applications"
    mkdir -p "$out/share/icons/hicolor/128x128/apps"
    cp "${finalAttrs.companionDesktopIcon}" \
       "$out/share/icons/hicolor/128x128/apps/bitfocusCompanion.png"
  '';
})
