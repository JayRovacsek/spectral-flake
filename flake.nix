{
  description = "A flake that downloads Spectral CLI binary";

  inputs = {
    devshell = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/devshell";
    };

    flake-utils.url = "github:numtide/flake-utils";

    git-hooks = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:cachix/git-hooks.nix";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      devshell,
      flake-utils,
      git-hooks,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          overlays = [ devshell.overlays.default ];
          inherit system;
        };
      in
      {
        checks.git-hooks = git-hooks.lib.${system}.run {
          src = self;
          hooks = {
            actionlint.enable = true;

            deadnix = {
              enable = true;
              settings.edit = true;
            };

            nixfmt-rfc-style = {
              enable = true;
              package = pkgs.nixfmt-rfc-style;
              settings.width = 120;
            };

            prettier = {
              enable = true;
              settings.write = true;
            };

            statix.enable = true;

            statix-write = {
              enable = true;
              name = "Statix Write";
              entry = "${pkgs.statix}/bin/statix fix";
              language = "system";
              pass_filenames = false;
            };
          };
        };

        devShells.default = pkgs.devshell.mkShell {
          devshell.startup.git-hooks.text = self.checks.${system}.git-hooks.shellHook;
          name = "spectral cli shell";
          packages =
            (with pkgs; [
              actionlint
              deadnix
              nixfmt-rfc-style
              prettier
              statix
            ])
            ++ (with self.packages.${system}; [ spectral-cli ]);
        };

        packages =
          let
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
            default = self.packages.${system}.spectral-cli;

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
          };
      }
    );
}
