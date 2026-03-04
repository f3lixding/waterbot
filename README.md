# high level ideation

A cluster / collection of ideas that are the foundation of this project. They
are located in docs/, with docs/DOODLE.md being the highest level (or entry
point) of the project

# flake
Some notes about the `flake.nix`.
Flakes usually produce 2 main attributes: 
- packages.default (this is referenced in `nix build`)
- devShells.default (this is referenced in `nix develop`)

## dev shell
All this needs is the right dependencies. 
This is a trial and error process:
1. nix develop
2. zig build 
3. observe missing dependencies in error
4. add to `buildInputs` of `pkgs.mkShell`
5. exit and go back to 1

## Bringing in deps
`nix build` runs in a sandbox and thus would not allow you to do the following that is typically done for a zig build: 
- Connect to the internet to download dependencies specified in `build.zig.zon`
- Write to cache that is outside of the sanbox

To get around that, you can use tools such as `zig2nix`, whose primary purpose is to take `build.zig.zon` and turn it into nix expression
```bash
# calls zon2json-lock if build.zig.zon2json-lock does not exist (requires network access)
nix run github:Cloudef/zig2nix -- zon2nix build.zig.zon
# alternatively run against the lock file (no network access required)
nix run github:Cloudef/zig2nix -- zon2nix build.zig.zon2json-lock
```

In the build script, use the generated artifact to symlink all the dependencies to `ZIG_GLOBAL_CACHE_DIR`:
```nix
preBuild = ''
  export ZIG_GLOBAL_CACHE_DIR=$PWD/zig-cache

  # Set up Zig dependency cache
  mkdir -p $ZIG_GLOBAL_CACHE_DIR/p
  find ${zigDeps} -maxdepth 1 -type l | while read dep; do
    ln -sf $(readlink "$dep") "$ZIG_GLOBAL_CACHE_DIR/p/$(basename "$dep")"
  done
'';
```

