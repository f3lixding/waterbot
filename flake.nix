{
  description = "For the waterbot";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
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
        pkgs = nixpkgs.legacyPackages.${system};
        zigTarget = "aarch64-linux-gnu";
        mkMainCompute =
          { stdenv, zig }:
          stdenv.mkDerivation {
            pname = "main_compute";
            version = "0.0.0";
            src = ./pkgs/main_compute;
            nativeBuildInputs = [ zig ];
            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-local"
              mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
              zig build -Dtarget=${zigTarget} -Doptimize=ReleaseSafe -p "$out"
            '';
            installPhase = "true";
          };
        mainCompute =
          if system == "x86_64-linux" then
            mkMainCompute {
              stdenv = pkgs.pkgsCross.aarch64-multiplatform.stdenv;
              zig = pkgs.zig;
            }
          else
            mkMainCompute {
              stdenv = pkgs.stdenv;
              zig = pkgs.zig;
            };
        buildApp = pkgs.writeShellApplication {
          name = "waterbot-build";
          text = ''
            exec ${./scripts/deploy-core.sh} build "$@"
          '';
        };
        deployApp = pkgs.writeShellApplication {
          name = "waterbot-deploy";
          text = ''
            exec ${./scripts/deploy-core.sh} deploy "$@"
          '';
        };
      in
      {
        packages.main_compute = mainCompute;
        packages.default = mainCompute;

        apps.build = flake-utils.lib.mkApp { drv = buildApp; };
        apps.deploy = flake-utils.lib.mkApp { drv = deployApp; };

        devShells.default = pkgs.mkShell {

          shellHook = ''
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      }
    );
}
