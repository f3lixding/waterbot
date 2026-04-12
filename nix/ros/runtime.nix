{
  pkgs,
  system,
  nix-ros-overlay,
}:
let
  jazzy = import ./mk-jazzy-pkgs.nix {
    inherit pkgs system nix-ros-overlay;
  };
in
{
  inherit (jazzy) rosPkgs ros;

  rosEnv =
    with jazzy.ros;
    buildEnv {
      paths = [ ros-core ];
    };
}
