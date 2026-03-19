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
          pkgs.patchelf
        ];

        # Because we are building this for raspberry pi 5
        zigTarget = "aarch64-linux-gnu";

        mkZigPkg =
          { name, src }:
          let
            targetPkgs = if system == "x86_64-linux" then pkgs.pkgsCross.aarch64-multiplatform else pkgs;

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
            buildInputs = [
              targetPkgs.libgpiod
              targetPkgs.libv4l
            ];

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
              zig build \
                -Dtarget=${zigTarget} \
                -Doptimize=ReleaseSafe \
                -Dgpiod-prefix=${targetPkgs.libgpiod} \
                -p "$out"
            '';

            postFixup = ''
              mkdir -p "$out/lib"
              cp -a ${targetPkgs.libgpiod}/lib/libgpiod.so* "$out/lib/"

              if [[ -d "$out/bin" ]]; then
                for bin_path in "$out"/bin/*; do
                  if [[ -f "$bin_path" && -x "$bin_path" ]]; then
                    # patchelf is a bin that alters the RPATH of a bin
                    # we do this because libgpiod is to be dynamically linked
                    # $ORIGIN is a sepcial token understood by the ELF dynamic loader
                    # It means 'relative to cwd of the bin'
                    patchelf --set-rpath '$ORIGIN/../lib' "$bin_path"
                  fi
                done
              fi
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
          buildInputs = [
            pkgs.libgpiod
            pkgs.libv4l
          ];
          shellHook = ''
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      }
    );
}
