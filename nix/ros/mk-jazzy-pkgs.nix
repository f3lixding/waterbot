{
  pkgs,
  system,
  nix-ros-overlay,
}:
let
  rosPkgs = import pkgs.path {
    inherit system;
    overlays = [
      (final: prev: {
        tbb_2022 = if prev ? tbb_2022_0 then prev.tbb_2022_0 else prev.tbb_2022;
      })
      nix-ros-overlay.overlays.default
    ];
  };
in
{
  inherit rosPkgs;
  ros = rosPkgs.rosPackages.jazzy;
}
