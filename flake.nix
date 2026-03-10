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

        nativeBuildInputs = [ pkgs.zigpkgs."0.15.2" ];

        # Because we are building this for raspberry pi 5
        zigTarget = "aarch64-linux-gnu";

        mkZigPkg =
          { name, src }:
          let
            stdenvFor =
              if system == "x86_64-linux" then pkgs.pkgsCross.aarch64-multiplatform.stdenv else pkgs.stdenv;

            zigDeps = import pkgs/${name}/build.zig.zon.nix {
              inherit (pkgs)
                lib
                linkFarm
                fetchurl
                fetchgit
                runCommandLocal
                ;
              inherit (pkgs) zig; # we might need to change this to keep it consistent with what is specified in nativeBuildInputs
              name = "zig-packages";
            };
          in
          stdenvFor.mkDerivation {
            pname = name;
            version = "0.0.0";

            inherit src nativeBuildInputs;

            preBuild = ''
              export ZIG_GLOBAL_CACHE_DIR=$PWD/zig-cache # might also need to change this since it looks like every pkg folder has their own zig cache
              # Set up Zig dependency cache
              mkdir -p $ZIG_GLOBAL_CACHE_DIR/p
              find ${zigDeps} -maxdepth 1 -type l | while read dep; do
                ln -sf $(readlink "$dep") "$ZIG_GLOBAL_CACHE_DIR/p/$(basename "$dep")"
              done
            '';

            buildPhase = ''
              runHook preBuild
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-local"
              mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
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
          shellHook = ''
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      }
    );
}
