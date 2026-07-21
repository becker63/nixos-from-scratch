final: prev:

let
  inherit (prev) lib stdenvNoCC;

  version = "5.0.373";
  sources = {
    aarch64-linux = {
      assetArch = "arm64";
      hash = "sha256-2q2KN7FbeP8pBIzW00r1kDQoeHhheG7IaGlwRd6zUEM=";
    };
    x86_64-linux = {
      assetArch = "x86_64";
      hash = "sha256-iDMq2RI4QF2rJB8mohNx5+DjDMRHiukNO4sCQfd+DgA=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "buildbuddy-cli: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
{
  buildbuddy-cli = stdenvNoCC.mkDerivation {
    pname = "buildbuddy-cli";
    inherit version;

    src = prev.fetchurl {
      url = "https://github.com/buildbuddy-io/bazel/releases/download/${version}/bazel-${version}-linux-${source.assetArch}";
      inherit (source) hash;
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/bb"
      runHook postInstall
    '';

    meta = {
      description = "BuildBuddy CLI";
      homepage = "https://www.buildbuddy.io/";
      license = lib.licenses.asl20;
      mainProgram = "bb";
      platforms = builtins.attrNames sources;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
}
