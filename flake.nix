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
          overlays = [
            zig-overlay.overlays.default
            (
              final: prev:
              if prev.stdenv.buildPlatform != prev.stdenv.hostPlatform then
                {
                  # Cross builds of gnutls try to execute a target-built helper while
                  # generating docs. Disable docs for cross package sets so transitive
                  # libv4l users remain cross-compilable.
                  gnutls = prev.gnutls.overrideAttrs (old: {
                    configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-doc" ];
                    outputs = [
                      "bin"
                      "dev"
                      "out"
                    ];
                    outputInfo = "dev";
                    outputDoc = "dev";
                  });
                }
              else
                { }
            )
          ];
        };

        zig = pkgs.zigpkgs."0.15.2";
        nativeBuildInputs = [
          zig
          pkgs.zls_0_15
          pkgs.binutils
          pkgs.patchelf
          pkgs.pkg-config
        ];

        # Because we are building this for raspberry pi 5
        zigTarget = "aarch64-linux-gnu";

        mkZigPkg =
          { name, src }:
          let
            targetPkgs = if system == "x86_64-linux" then pkgs.pkgsCross.aarch64-multiplatform else pkgs;
            effectiveSrc =
              if name == "main_compute" then
                pkgs.runCommandLocal "main_compute-src" { } ''
                  mkdir -p "$out/main_compute" "$out/openzv"
                  cp -R ${src}/. "$out/main_compute/"
                  cp -R ${pkgsDir + "/openzv"}/. "$out/openzv/"
                  cp -R ${pkgsDir + "/perception_pipeline"}/. "$out/perception_pipeline/"
                ''
              else
                src;
            needsOpenzvToolchain = builtins.elem name [
              "openzv"
              "main_compute"
            ];
            extraBuildInputs = pkgs.lib.optionals needsOpenzvToolchain [ targetPkgs.opencv ];
            extraBuildFlags =
              pkgs.lib.optionals needsOpenzvToolchain [
                "-Dopencv-prefix=${targetPkgs.opencv}"
                "-Dcxx-compiler=${targetPkgs.stdenv.cc}/bin/${targetPkgs.stdenv.cc.targetPrefix}c++"
                "-Dlibstdcpp-dir=${targetPkgs.stdenv.cc.cc.lib}/lib"
              ]
              ++ pkgs.lib.optionals (name == "openzv") [
                "-Dldso-path=${targetPkgs.stdenv.cc.libc.out}/lib/ld-linux-aarch64.so.1"
              ];

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
          stdenvFor.mkDerivation ({
            pname = name;
            version = "0.0.0";

            src = effectiveSrc;
            dontUnpack = name == "main_compute";
            postPhases = [ "rewriteBundledRpathsPhase" ];
            inherit nativeBuildInputs;
            buildInputs = [
              targetPkgs.libgpiod
              targetPkgs.libv4l
            ]
            ++ extraBuildInputs;

            preBuild = ''
              ${pkgs.lib.optionalString (name == "main_compute") ''
                cp -R "$src"/. .
                chmod -R +w .
                cd main_compute
              ''}
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
                ${pkgs.lib.concatStringsSep " \\\n                " extraBuildFlags} \
                -p "$out"

              copy_libs() {
                local pattern
                local lib_path
                for pattern in "$@"; do
                  for lib_path in $pattern; do
                    if [[ -e "$lib_path" ]]; then
                      cp -a "$lib_path" "$out/lib/"
                    fi
                  done
                done
              }

              mkdir -p "$out/lib"
              chmod u+w "$out"
              chmod u+w "$out/lib"
              copy_libs \
                "${targetPkgs.libgpiod}/lib/libgpiod.so*"
              ${pkgs.lib.optionalString needsOpenzvToolchain ''
                copy_libs \
                  "${targetPkgs.opencv}/lib/libopencv*.so*" \
                  "${targetPkgs.ocl-icd}/lib/libOpenCL.so*" \
                  "${targetPkgs.openblas}/lib/libopenblas.so*" \
                  "${targetPkgs.openblas}/lib/libopenblasp-*.so" \
                  "${targetPkgs.libjpeg.out}/lib/libjpeg.so*" \
                  "${targetPkgs.libpng}/lib/libpng*.so*" \
                  "${targetPkgs.libtiff.out}/lib/libtiff*.so*" \
                  "${targetPkgs.openjpeg}/lib/libopenjp2.so*" \
                  "${targetPkgs.openexr.out}/lib/libOpenEXR*.so*" \
                  "${targetPkgs.openexr.out}/lib/libIex*.so*" \
                  "${targetPkgs.openexr.out}/lib/libIlmThread*.so*" \
                  "${targetPkgs.imath.out}/lib/libImath*.so*" \
                  "${targetPkgs.lerc.out}/lib/libLerc.so*" \
                  "${targetPkgs.zstd.out}/lib/libzstd.so*" \
                  "${targetPkgs.libdeflate}/lib/libdeflate.so*" \
                  "${targetPkgs.xz.out}/lib/liblzma.so*" \
                  "${targetPkgs.zlib}/lib/libz.so*" \
                  "${targetPkgs.stdenv.cc.cc.lib}/lib/libstdc++.so*" \
                  "${targetPkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so*" \
                  "${targetPkgs.stdenv.cc.cc.lib}/lib/libgomp.so*" \
                  "${targetPkgs.gfortran.cc.lib}/lib/libgfortran.so*" \
                  "${targetPkgs.libwebp}/lib/libwebp.so*" \
                  "${targetPkgs.libwebp}/lib/libwebpmux.so*" \
                  "${targetPkgs.libwebp}/lib/libwebpdemux.so*" \
                  "${targetPkgs.libwebp}/lib/libsharpyuv.so*"
              ''}
            '';

            rewriteBundledRpathsPhase = ''
              if [[ -d "$out/lib" ]]; then
                find "$out/lib" -maxdepth 1 -type f -name '*.so*' | while read -r lib_path; do
                  if readelf -h "$lib_path" >/dev/null 2>&1; then
                    chmod u+w "$lib_path"
                    patchelf --force-rpath --set-rpath '$ORIGIN' "$lib_path"
                  fi
                done
              fi

              if [[ -d "$out/bin" ]]; then
                for bin_path in "$out"/bin/*; do
                  if [[ -f "$bin_path" && -x "$bin_path" ]]; then
                    chmod u+w "$bin_path"
                    patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "$bin_path"
                  fi
                done
              fi
            '';

            installPhase = "true";
          });

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

        flashRaspiosApp = pkgs.writeShellApplication {
          name = "waterbot-flash-raspios";
          text = ''
            exec ${./scripts/flash-raspios} "$@"
          '';
        };
      in
      {
        packages =
          zigPackages
          // (if defaultPkgName == null then { } else { default = zigPackages.${defaultPkgName}; });

        checks = pkgs.lib.optionalAttrs (builtins.hasAttr "openzv" zigPackages) {
          openzv = pkgs.stdenv.mkDerivation {
            pname = "openzv-tests";
            version = "0.0.0";
            src = pkgsDir + "/openzv";
            nativeBuildInputs = nativeBuildInputs;
            buildInputs = [
              pkgs.opencv
              pkgs.stdenv.cc.cc
              pkgs.stdenv.cc
            ];

            buildPhase = ''
              export HOME="$TMPDIR"
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-local"
              mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
              zig build test \
                -Doptimize=ReleaseSafe \
                -Dopencv-prefix=${pkgs.opencv} \
                -Dcxx-compiler=${pkgs.stdenv.cc}/bin/c++ \
                -Dldso-path=${pkgs.stdenv.cc.libc.out}/lib/ld-linux-x86-64.so.2 \
                -Dlibstdcpp-dir=${pkgs.stdenv.cc.cc.lib}/lib

              zig build smoke \
                -Doptimize=ReleaseSafe \
                -Dopencv-prefix=${pkgs.opencv} \
                -Dcxx-compiler=${pkgs.stdenv.cc}/bin/c++ \
                -Dldso-path=${pkgs.stdenv.cc.libc.out}/lib/ld-linux-x86-64.so.2 \
                -Dlibstdcpp-dir=${pkgs.stdenv.cc.cc.lib}/lib
            '';

            installPhase = ''
              touch "$out"
            '';
          };
        };

        apps.build = flake-utils.lib.mkApp { drv = buildApp; };
        apps.deploy = flake-utils.lib.mkApp { drv = deployApp; };
        apps.flash-raspios = flake-utils.lib.mkApp { drv = flashRaspiosApp; };

        devShells.default = pkgs.mkShell {
          inherit nativeBuildInputs;
          buildInputs = [
            pkgs.libgpiod
            pkgs.libv4l
            pkgs.opencv
          ];
          shellHook = ''
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      }
    );
}
