{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  version = "0.0.16";
  sources = {
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-lj0DhKqnx5h3hHnEVnP5BRpAOd2JGu+PiXjSoaYot08=";
    };
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-1gzboBm85FG8w6FUeMxbnLEScLBJ9bVuo5qAtRf4sRc=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "research-graph-tunnel-client";
  inherit version;
  src = fetchurl {
    url = "https://github.com/openai/tunnel-client/releases/download/v${version}/tunnel-client-v${version}-linux-${source.arch}.zip";
    inherit (source) hash;
  };
  nativeBuildInputs = [ unzip ];
  dontUnpack = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    unzip "$src" -d release
    install -Dm755 release/tunnel-client "$out/bin/tunnel-client"
    install -Dm755 release/cloudflared "$out/bin/cloudflared"
    install -Dm644 release/cloudflared-manifest.json "$out/bin/cloudflared-manifest.json"
    mkdir -p "$out/share/doc/research-graph-tunnel-client"
    install -m644 release/LICENSE release/NOTICE release/*-licenses.txt release/*.spdx.json "$out/share/doc/research-graph-tunnel-client/"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/tunnel-client" --version | grep -F '${version}+'
    "$out/bin/tunnel-client" help quickstart >/dev/null
  '';
  meta = {
    description = "OpenAI Secure MCP Tunnel client for the research graph app";
    homepage = "https://github.com/openai/tunnel-client";
    license = lib.licenses.asl20;
    mainProgram = "tunnel-client";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
