{
  pkgs,
  system,
}:
let
  assets = {
    x86_64-linux = {
      platform = "x86_64-linux";
      hash = "1dlnzxnxbya8fl3xc0ivrb6y6z3rnbx0zxyxn5wfhvmql1idbmny";
    };
    aarch64-linux = {
      platform = "aarch64-linux";
      hash = "1mxyla09dp6jx2997z7pildpky2bhmncknqr4np71sq1sa9x4323";
    };
    aarch64-darwin = {
      platform = "aarch64-macos";
      hash = "0nc3jn14kvwn88jy9balkc2z2x6jfs90x12ak22px2jmz14wagmr";
    };
    x86_64-darwin = {
      platform = "x86_64-macos";
      hash = "15pbsfd4jdgfwzqjbf22vi1z9g2chx80m72xmbndman1jvm1dxs9";
    };
  };
  asset = assets.${system} or (throw "Unsupported system for zls prebuilt binary: ${system}");
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "zls";
  version = "0.16.0";

  src = pkgs.fetchurl {
    url = "https://github.com/zigtools/zls/releases/download/0.16.0/zls-${asset.platform}.tar.xz";
    sha256 = asset.hash;
  };

  nativeBuildInputs = [
    pkgs.xz
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.autoPatchelfHook
  ];

  buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.stdenv.cc.cc.lib
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    tar -xJf "$src" -C "$TMPDIR"
    install -m755 "$TMPDIR/zls" "$out/bin/zls"

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Zig LSP implementation and language server";
    homepage = "https://github.com/zigtools/zls";
    license = licenses.mit;
    mainProgram = "zls";
    platforms = builtins.attrNames {
      x86_64-linux = null;
      aarch64-linux = null;
      x86_64-darwin = null;
      aarch64-darwin = null;
    };
  };
}
