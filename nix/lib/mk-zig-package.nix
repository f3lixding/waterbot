{
  pkgs,
  system,
  zig,
  nativeBuildInputs,
  pkgsDir,
  zigTarget,
}:
{
  name,
  src,
  nativeTarget ? false,
  rosPrefix ? null,
}:
let
  targetPkgs =
    if nativeTarget then
      pkgs
    else if system == "x86_64-linux" then
      pkgs.pkgsCross.aarch64-multiplatform
    else
      pkgs;

  effectiveSrc =
    if name == "main_compute" then
      pkgs.runCommandLocal "main_compute-src" { } ''
        mkdir -p "$out/main_compute" "$out/openzv" "$out/perception_pipeline" "$out/ros2"
        cp -R ${src}/. "$out/main_compute/"
        cp -R ${pkgsDir + "/openzv"}/. "$out/openzv/"
        cp -R ${pkgsDir + "/perception_pipeline"}/. "$out/perception_pipeline/"
        cp -R ${pkgsDir + "/ros2"}/. "$out/ros2/"
      ''
    else
      src;

  needsOpenzvToolchain = builtins.elem name [
    "openzv"
    "main_compute"
  ];

  rosEnabled = rosPrefix != null;
  rosLibDir = if rosEnabled then "${toString rosPrefix}/lib" else null;
  targetFlag = if nativeTarget || system != "x86_64-linux" then "" else "-Dtarget=${zigTarget}";

  extraBuildInputs =
    pkgs.lib.optionals needsOpenzvToolchain [ targetPkgs.opencv ]
    ++ pkgs.lib.optionals rosEnabled [ rosPrefix ];

  extraBuildFlags =
    pkgs.lib.optionals needsOpenzvToolchain [
      "-Dopencv-prefix=${targetPkgs.opencv}"
      "-Dcxx-compiler=${targetPkgs.stdenv.cc}/bin/${targetPkgs.stdenv.cc.targetPrefix}c++"
      "-Dlibstdcpp-dir=${targetPkgs.stdenv.cc.cc.lib}/lib"
    ]
    ++ pkgs.lib.optionals (name == "main_compute" && rosEnabled) [
      "-Dros-prefix=${toString rosPrefix}"
    ]
    ++ pkgs.lib.optionals (name == "openzv") [
      "-Dldso-path=${targetPkgs.stdenv.cc.libc.out}/lib/ld-linux-aarch64.so.1"
    ];

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
targetPkgs.stdenv.mkDerivation {
  pname = name;
  version = "0.0.0";

  src = effectiveSrc;
  dontUnpack = name == "main_compute";
  dontConfigure = true;
  inherit nativeBuildInputs;
  buildInputs = [
    targetPkgs.libgpiod
    targetPkgs.libv4l
  ] ++ extraBuildInputs;

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
    zig build ${targetFlag} \
      -Doptimize=ReleaseSafe \
      -Dgpiod-prefix=${targetPkgs.libgpiod} \
      ${pkgs.lib.concatStringsSep " \\\n      " extraBuildFlags} \
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

  preFixup = ''
    ${pkgs.lib.optionalString nativeTarget ''
      interpreter_path=""
      if [[ -n "''${NIX_CC:-}" && -f "$NIX_CC/nix-support/dynamic-linker" ]]; then
        interpreter_path="$(<"$NIX_CC/nix-support/dynamic-linker")"
      fi
    ''}

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
          ${pkgs.lib.optionalString nativeTarget ''
            if [[ -n "$interpreter_path" ]]; then
              patchelf --set-interpreter "$interpreter_path" "$bin_path"
            fi
          ''}
          patchelf --force-rpath --set-rpath '$ORIGIN/../lib${pkgs.lib.optionalString rosEnabled ":${rosLibDir}"}' "$bin_path"
        fi
      done
    fi
  '';

  installPhase = "true";
}
