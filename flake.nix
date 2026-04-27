{
  description = "For the waterbot";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    ros-nixpkgs.url = "github:lopsided98/nixpkgs?ref=nix-ros";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nix-ros-overlay.inputs.nixpkgs.follows = "nixpkgs";
    nix-ros-gz.url = "github:f3lixding/nix-ros-gz";
  };

  outputs =
    {
      nixpkgs,
      ros-nixpkgs,
      zig-overlay,
      nix-ros-overlay,
      nix-ros-gz,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        crossGnutlsOverlay =
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
            { };

        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            zig-overlay.overlays.default
            crossGnutlsOverlay
          ];
        };

        simRosPkgs = import ros-nixpkgs {
          inherit system;
        };

        rosClientExtraPackages = ros: [
          ros.turtlesim
          ros.rqt
          ros.rqt-common-plugins
          ros.rqt-service-caller
          ros.rqt-graph
          ros.rqt-topic
        ];

        runtimeRos = nix-ros-gz.lib."build-ros-env" {
          pkgs = pkgs;
          inherit system nix-ros-overlay;
          extraPackages = rosClientExtraPackages;
        };

        simRos = nix-ros-gz.lib."build-ros-env" {
          pkgs = simRosPkgs;
          inherit system nix-ros-overlay;
          extraPackages = rosClientExtraPackages;
        };

        mainComputeRosEnv = runtimeRos.rosEnv;
        mainComputeRosEnvSim = simRos.rosEnv;

        sim =
          let
            simArgs = {
              pkgs = simRosPkgs;
              inherit system nix-ros-overlay;
              # Preserve waterbot's current sim shell extras on top of nix-ros-gz.
              extraRosPackages = ros: [
                ros.ros-gz-sim-demos
                ros.sdformat-urdf
                ros.rviz2
              ];
            };
          in
          nix-ros-gz.lib.sim simArgs;

        simResourcePathExport = ''
          export GZ_PARTITION="''${GZ_PARTITION:-gazebo$UID}"
          export GZ_SIM_RESOURCE_PATH="${pkgs.lib.concatStringsSep ":" [
            "${sim.ros.ros-gz-sim-demos}/share"
            "$PWD/sim"
          ]}''${GZ_SIM_RESOURCE_PATH:+:''${GZ_SIM_RESOURCE_PATH}}"
        '';

        zig = pkgs.zigpkgs."0.16.0";
        # change this when we finally are able to move to zig ^0.16.0
        zls = import ./nix/zls_0_16 {
          inherit pkgs system;
        };
        pkgsDir = ./pkgs;
        zigTarget = "aarch64-linux-gnu";

        nativeBuildInputs = [
          zig
          zls
          pkgs.binutils
          pkgs.patchelf
          pkgs.pkg-config
        ];

        commonShellBuildInputs = [
          pkgs.libgpiod
          pkgs.libv4l
          pkgs.opencv
        ];

        commonShellBuildInputsSim = [
          simRosPkgs.libgpiod
          simRosPkgs.libv4l
          simRosPkgs.opencv
        ];

        mkZigPkg = import ./nix/lib/mk-zig-package.nix {
          inherit
            pkgs
            system
            zig
            nativeBuildInputs
            pkgsDir
            zigTarget
            ;
        };

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
              rosPrefix = if name == "main_compute" && system == "aarch64-linux" then mainComputeRosEnv else null;
            };
          }) pkgNames
        );

        packageVariants = pkgs.lib.optionalAttrs (builtins.elem "main_compute" pkgNames) {
          main_compute-ros = mkZigPkg {
            name = "main_compute";
            src = pkgsDir + "/main_compute";
            nativeTarget = true;
            rosPrefix = mainComputeRosEnv;
          };
        };

        defaultPkgName =
          if builtins.hasAttr "main_compute" zigPackages then
            "main_compute"
          else if pkgNames != [ ] then
            builtins.head pkgNames
          else
            null;

        exportedPackages =
          zigPackages
          // {
            inherit zig;
            inherit zls;
          }
          // packageVariants
          // (if defaultPkgName == null then { } else { default = zigPackages.${defaultPkgName}; });

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
        packages = exportedPackages;

        checks = pkgs.lib.optionalAttrs (builtins.hasAttr "openzv" zigPackages) {
          openzv = pkgs.stdenv.mkDerivation {
            pname = "openzv-tests";
            version = "0.0.0";
            src = pkgsDir + "/openzv";
            inherit nativeBuildInputs;
            buildInputs = [
              pkgs.opencv
              pkgs.stdenv.cc.cc
              pkgs.stdenv.cc
            ];

            buildPhase = ''
              export HOME="$TMPDIR"
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-local"
              unset NIX_CFLAGS_COMPILE
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
          packages = [ mainComputeRosEnv ];
          buildInputs = commonShellBuildInputs;
          shellHook = ''
            # because we might as well
            ${sim.shellHook}
            ${simResourcePathExport}
            unset NIX_CFLAGS_COMPILE
            export WATERBOT_GPIOD_PREFIX="${pkgs.libgpiod}"
            export WATERBOT_ROS_PREFIX="${mainComputeRosEnv}"
            exec ${pkgs.zsh}/bin/zsh
          '';
        };

        devShells.sim = pkgs.mkShell {
          inherit nativeBuildInputs;
          packages = sim.packages ++ [ mainComputeRosEnvSim ];
          buildInputs = commonShellBuildInputsSim;
          shellHook = ''
            ${sim.shellHook}
            ${simResourcePathExport}
            unset NIX_CFLAGS_COMPILE
            export WATERBOT_GPIOD_PREFIX="${simRosPkgs.libgpiod}"
            export WATERBOT_ROS_PREFIX="${mainComputeRosEnvSim}"
            exec ${pkgs.zsh}/bin/zsh
          '';
        };
      }
    );
}
