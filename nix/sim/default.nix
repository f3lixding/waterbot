{
  pkgs,
  system,
  nix-ros-overlay,
  extraRosPackages ? (_: [ ]),
  extraResourcePaths ? (_: [ ]),
}:
let
  lib = pkgs.lib;

  rosPkgs = import pkgs.path {
    inherit system;
    overlays = [
      (final: prev: {
        tbb_2022 = if prev ? tbb_2022_0 then prev.tbb_2022_0 else prev.tbb_2022;
      })
      nix-ros-overlay.overlays.default
    ];
  };

  ros = rosPkgs.rosPackages.jazzy.overrideScope (
    rosFinal: rosPrev: {
      # nix-ros-overlay currently has stale fetchpatch hashes for Ogre.
      gz-ogre-next-vendor =
        (rosFinal.lib.patchAmentVendorGit rosPrev.gz-ogre-next-vendor {
          patchesFor.gz_ogre_next_vendor = [
            (rosPkgs.fetchpatch2 {
              url = "https://github.com/OGRECave/ogre-next/commit/98c9095c6e288fceb59ccb3504d9127d88eb1b51.patch";
              hash = "sha256-m1CkqcD2e0WW6zIEVOCmTQk7Fm1r7J67pekZJSc+aiA=";
            })
            (rosPkgs.fetchpatch2 {
              url = "https://github.com/OGRECave/ogre-next/commit/37d4876eb71c70b9eb3464e5b72c6e6d6be03232.patch";
              hash = "sha256-vrVv2PWbyDqM6+fhyg3N5QhUzwvJrmGdTzULfvLSyUY=";
            })
            (rosPkgs.fetchpatch2 {
              url = "https://github.com/OGRECave/ogre-next/commit/96a3bb016b2c9b4f9cca9df1a65d619220e21d78.patch";
              hash = "sha256-ZHQNF1u5+OvdmN1E7uHxeeWO9x8gzbOrIj/VAJVw9Ps=";
            })
          ];
        }).overrideAttrs
          (
            {
              postPatch ? "",
              ...
            }:
            {
              postPatch = postPatch + ''
                substituteInPlace CMakeLists.txt \
                  --replace-fail 'CMAKE_ARGS' 'CMAKE_ARGS -DOGRE_CONFIG_ENABLE_STBI:BOOL=ON'
              '';
              dontFixCmake = true;
            }
          );

      rviz-ogre-vendor = rosPrev.rviz-ogre-vendor.overrideAttrs (
        { postPatch ? "", ... }:
        {
          # OGRE 1.12.10 needs an explicit policy minimum with newer CMake.
          postPatch = postPatch + ''
            substituteInPlace CMakeLists.txt \
              --replace-fail '-DCMAKE_POLICY_DEFAULT_CMP0074=NEW' '-DCMAKE_POLICY_DEFAULT_CMP0074=NEW
                -DCMAKE_POLICY_VERSION_MINIMUM=3.5'
          '';
        }
      );
    }
  );

  baseRosPackages = with ros; [
    ros-core
    simulation-interfaces
    ros-gz-bridge
    ros-gz-interfaces
    ros-gz-sim
    sdformat-urdf
    rviz2
  ];

  rosEnv =
    with ros;
    buildEnv {
      paths = baseRosPackages ++ extraRosPackages ros;
    };

  resourcePaths = extraResourcePaths ros;

  resourcePathExport = lib.optionalString (resourcePaths != [ ]) ''
    export GZ_SIM_RESOURCE_PATH="${lib.concatStringsSep ":" resourcePaths}''${GZ_SIM_RESOURCE_PATH:+:''${GZ_SIM_RESOURCE_PATH}}"
  '';
in
{
  inherit ros rosEnv;

  packages = [ rosEnv ];

  shellHook = ''
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DISPLAY="''${DISPLAY:-:0}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
    export XDG_SESSION_TYPE="''${XDG_SESSION_TYPE:-wayland}"

    export GZ_IP="''${GZ_IP:-127.0.0.1}"
    export GZ_PARTITION="''${GZ_PARTITION:-gazebo$UID}"
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-xcb}"

    ${resourcePathExport}

    unalias gz 2>/dev/null || true
  '';
}
