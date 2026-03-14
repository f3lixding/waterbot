{
  description = "For the waterbot";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      zig-overlay,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };

        zig = pkgs.zigpkgs."0.15.2";
        nativeBuildInputs = [
          zig
          pkgs.zls_0_15
        ];

        # Because we are building this for raspberry pi 5
        zigTarget = "aarch64-linux-gnu";

        mkZigPkg =
          { name, src }:
          let
            targetPkgs =
              if system == "x86_64-linux" then pkgs.pkgsCross.aarch64-multiplatform else pkgs;

            stdenvFor = targetPkgs.stdenv;

            zigDepsFile = pkgsDir + "/${name}/build.zig.zon.nix";
            zigDeps =
              if builtins.pathExists zigDepsFile then
                import zigDepsFile {
                  inherit (pkgs)
                    lib
                    linkFarm
                    fetchurl
                    fetchgit
                    runCommandLocal
                    ;
                  inherit zig;
                  name = "zig-packages";
                }
              else
                null;
            zigDepsPath = if zigDeps == null then "" else toString zigDeps;
          in
          stdenvFor.mkDerivation {
            pname = name;
            version = "0.0.0";

            inherit src nativeBuildInputs;
            buildInputs = [ targetPkgs.libgpiod ];

            preBuild = ''
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-local"
              mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
              if [ -n "${zigDepsPath}" ]; then
                mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
                find ${zigDepsPath} -maxdepth 1 -type l | while read dep; do
                  ln -sf $(readlink "$dep") "$ZIG_GLOBAL_CACHE_DIR/p/$(basename "$dep")"
                done
              fi
            '';

            buildPhase = ''
              runHook preBuild
              zig build -Dtarget=${zigTarget} -Doptimize=ReleaseSafe -p "$out"
            '';

            installPhase = "true";
          };

        pkgsDir = ./pkgs;

        pkgsEntries = builtins.readDir pkgsDir;

        pkgNames = builtins.filter (
          name: pkgsEntries.${name} == "directory" && builtins.pathExists (pkgsDir + "/${name}/build.zig")
        ) (builtins.attrNames pkgsEntries);

        zigPackages = builtins.listToAttrs (
          map (name: {
            inherit name;
            value = mkZigPkg {
              inherit name;
              src = pkgsDir + "/${name}";
            };
          }) pkgNames
        );

        defaultPkgName =
          if builtins.hasAttr "main_compute" zigPackages then
            "main_compute"
          else if pkgNames != [ ] then
            builtins.head pkgNames
          else
            null;

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
        packages =
          zigPackages
          // (if defaultPkgName == null then { } else { default = zigPackages.${defaultPkgName}; });

        apps.build = flake-utils.lib.mkApp { drv = buildApp; };
        apps.deploy = flake-utils.lib.mkApp { drv = deployApp; };

        devShells.default = pkgs.mkShell {
          inherit nativeBuildInputs;
          buildInputs = [ pkgs.libgpiod ];
          shellHook = ''
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      }
    );
}
