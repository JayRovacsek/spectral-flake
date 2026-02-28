{
  description = "A flake that builds Spectral CLI from source";

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

    spectral = {
      url = "github:stoplightio/spectral";
      flake = false;
    };
  };

  outputs =
    {
      devshell,
      flake-utils,
      git-hooks,
      nixpkgs,
      self,
      spectral,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          overlays = [ devshell.overlays.default ];
          inherit system;
        };

        yarnDeps = pkgs.stdenv.mkDerivation {
          pname = "spectral-deps";
          version = "git";
          src = spectral;

          nativeBuildInputs = [
            pkgs.yarn-berry
            pkgs.nodejs
            pkgs.cacert
          ];

          buildPhase = ''
            export HOME=$(mktemp -d)
            export NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export YARN_ENABLE_TELEMETRY=0
            export YARN_ENABLE_GLOBAL_CACHE=false
            export YARN_CACHE_FOLDER=$out
            yarn install --immutable
          '';

          installPhase = "true";

          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
          outputHash = "sha256-ZdwfiXDp3raLxPVywPxyndwviPiMtKFxQV1v3Ptu26E=";
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
          packages = self.checks.${system}.git-hooks.enabledPackages;
        };

        packages = {
          default = self.packages.${system}.spectral-cli;

          spectral-cli = pkgs.stdenv.mkDerivation {
            pname = "spectral-cli";
            version = "git";
            src = spectral;

            nativeBuildInputs = [
              pkgs.yarn-berry
              pkgs.nodejs
              pkgs.makeWrapper
            ];

            buildPhase = ''
              export HOME=$(mktemp -d)
              export YARN_ENABLE_TELEMETRY=0
              export YARN_ENABLE_GLOBAL_CACHE=false
              export YARN_CACHE_FOLDER=${yarnDeps}
              yarn install --immutable --immutable-cache

              # Now build the project
              yarn build
            '';

            installPhase = ''
              mkdir -p $out/bin
              mkdir -p $out/libexec/spectral

              cp -r . $out/libexec/spectral

              makeWrapper ${pkgs.nodejs}/bin/node $out/bin/spectral \
                --add-flags "$out/libexec/spectral/packages/cli/dist/index.js"
            '';
          };
        };
      }
    );
}
