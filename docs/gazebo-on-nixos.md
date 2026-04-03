# Gazebo on NixOS

This note records what it took to get Gazebo running on NixOS and what to
expect from similar packaging work in the future.

## Short answer

No, packaging software on Nix is not usually this painful.

This case was painful because it combined several hard problems:

- Gazebo is not a first-class NixOS target
- the easiest available build path was an Ubuntu-oriented conda package
- the app is a GUI program with Qt and X11 / Wayland assumptions
- Gazebo also relies on transport discovery between separate processes

That stack is much more fragile than a normal CLI tool or library package.

## Rough effort expectations

For an average NixOS user, a rough rule of thumb is:

- Already packaged in `nixpkgs`: a few minutes
- Simple upstream binary or AppImage: 30 minutes to 2 hours
- Unsupported GUI application: a few hours
- Robotics / simulation stack with graphics and IPC: half a day to multiple
  days

This Gazebo setup landed in the last category.

## What made this case hard

### This was not native Nix packaging

The working setup is not a clean native derivation of Gazebo from source.

It is closer to:

- a Nix-installed wrapper
- an FHS environment for foreign runtime assumptions
- a `micromamba`-managed Gazebo environment from `conda-forge`

That is often the pragmatic path on NixOS, but it means debugging foreign
runtime behavior instead of only debugging a derivation.

### GUI problems and launch problems looked similar

Several failures initially looked like "Gazebo opened, but the scene is black".
In practice, they came from different layers:

- missing or unusable X11 display for the GUI
- broken combined launcher behavior
- GUI and server not discovering each other on Gazebo transport

Those problems can produce very similar visible symptoms.

### Gazebo uses separate GUI and server processes

The quick-start flow depends on the GUI and server seeing each other and
handing off the selected world correctly.

The important log clue was:

- `Waited for 10s for a subscriber to [/gazebo/starting_world] and got none.`

When that appears in `~/.gz/auto_default.log`, the selected scene was not
accepted by a live server process. That is not a rendering problem.

## Working shape

The final shape that worked was:

- launch Gazebo through an FHS wrapper
- bootstrap Gazebo from `conda-forge` into a local `micromamba` env
- provide a wrapper override for Gazebo's `sim` command
- set `GZ_IP=127.0.0.1` by default
- set a stable `GZ_PARTITION` by default
- repair missing `DISPLAY` when exactly one X socket is present

The key point is that the transport identity had to be made stable enough for
the GUI and server to discover each other reliably.

## Lessons learned

- If `gazebo split shapes` starts the server correctly, then worlds, physics,
  and basic simulation are probably fine.
- If the menu opens but scene selection hangs, inspect `~/.gz/auto_default.log`
  before assuming the renderer is broken.
- If Qt reports `could not connect to display`, that is a GUI environment
  problem, not a Gazebo world problem.
- Unsupported robotics stacks on NixOS are often runtime-debugging exercises,
  not just packaging exercises.

## Practical recommendation

If the goal is to learn ROS and simulation quickly, Ubuntu is still the easier
path.

If the goal is to stay on NixOS and you are willing to debug wrappers, env
vars, graphics, and IPC issues, Gazebo can still be made to work.

Use the NixOS path when the host environment matters. Use Ubuntu when learning
speed matters more than packaging purity.
