{
  pkgs,
  system,
  nix-ros-overlay,
}:
let
  lib = pkgs.lib;
  jazzy = import ./mk-jazzy-pkgs.nix {
    inherit pkgs system nix-ros-overlay;
  };
in
{
  inherit (jazzy) rosPkgs ros;

  rosEnv =
    with jazzy.ros;
    buildEnv {
      paths = [
        ros-core
        rcl
        (lib.getDev rcl)
        rcutils
        (lib.getDev rcutils)
        rosidl-runtime-c
        (lib.getDev rosidl-runtime-c)
        # tutorial related; TODO: delete it
        turtlesim
        rqt
        rqt-common-plugins
        rqt-service-caller
        rqt-graph
        rqt-topic
      ];
    };
}
