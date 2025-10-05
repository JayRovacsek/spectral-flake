{
  description = "A flake that downloads Spectral CLI binary";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        pname = "spectral-cli";
        version = "6.15.0";
        src = pkgs.fetchFromGitHub {
          owner = "stoplightio";
          repo = "spectral";
          tag = "v${version}";
          hash = "sha256-6ywvyZe0ol2B7ZMS/9zWkDKu4u/9dh2fsPegJ6FlLAs=";
        };

        supportedArchitectures = builtins.toJSON {
          os = [
            "darwin"
            "linux"
          ];
          cpu = [
            "x64"
            "arm64"
          ];
          libc = [
            "glibc"
            "musl"
          ];
        };

        offlineCache = pkgs.stdenv.mkDerivation {
          name = "yarn-offline-cache";
          inherit src;

          env.CI = "1";

          nativeBuildInputs = with pkgs; [
            cacert
            gitMinimal
            yarn
          ];

          buildPhase = ''
            ${pkgs.coreutils}/bin/mkdir -p $out
            export HOME=$(mktemp -d)
            ${pkgs.yarn-berry}/bin/yarnconfig set enableTelemetry false
            ${pkgs.yarn-berry}/bin/yarnconfig set cacheFolder $out
            ${pkgs.yarn-berry}/bin/yarnconfig set enableGlobalCache false
            ${pkgs.yarn-berry}/bin/yarnconfig set supportedArchitectures --json '${supportedArchitectures}'
            ${pkgs.yarn-berry}/bin/yarninstall --immutable --mode=skip-build

            runHook postBuild
          '';

          dontInstall = true;

          outputHashMode = "recursive";
          outputHash = "sha256-e5wL6VLr0gzLGWExW507bwHD8hTa4wTxwyzC6xoAUcw=";
        };
      in
      {
        packages = {
          inherit offlineCache;
          spectral-cli = pkgs.stdenv.mkDerivation {
            inherit pname src version;

            env.CI = "1";

            strictDeps = true;

            nativeBuildInputs = with pkgs; [
              makeWrapper
              yarn-berry
            ];

            configurePhase = ''
              runHook preConfigure

              export HOME=$(mktemp -d)
              ${pkgs.yarn-berry}/bin/yarn config set enableTelemetry false
              ${pkgs.yarn-berry}/bin/yarn config set enableGlobalCache false
              ${pkgs.yarn-berry}/bin/yarn config set cacheFolder ${offlineCache}
              ${pkgs.yarn-berry}/bin/yarn install

              runHook postConfigure
            '';

            buildPhase = ''
              runHook preBuild
              ${pkgs.yarn-berry}/bin/yarn run build
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              ${pkgs.coreutils}/bin/mkdir -p "$out/share"
              ${pkgs.coreutils}/bin/cp -r . "$out/share/spectral"

              ${pkgs.coreutils}/bin/chmod +x $out/share/spectral/packages/cli/dist/index.js

              makeWrapper $out/share/spectral/packages/cli/dist/index.js "$out/bin/spectral" \
              --set PATH ${
                pkgs.lib.makeBinPath [
                  pkgs.nodejs
                ]
              }

              runHook postInstall
            '';
          };

          default = self.packages.${system}.spectral-cli;
        };
      }
    );
}
