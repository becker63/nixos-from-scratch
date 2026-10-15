{
  lib,
  buildNpmPackage,
  nodejs_24,
  makeWrapper,
  python3,
  ripgrep,
  git,
  bash,
  cacert,
  typescript-language-server,
  nixd,
}:
buildNpmPackage {
  pname = "pi-runtime";
  version = "1.0.4";
  nodejs = nodejs_24;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./validate.mjs
      ./credential.py
      ./guidance.md
      ./skill
      ./semantic-trace.ts
      ./semantic-fabric-patch.mjs
      ./semantic-trace.test.mjs
      ./semantic-state.ts
      ./semantic-policy.ts
      ./semantic-controller.ts
      ./semantic-extension.ts
      ./semantic-control-patch.mjs
      ./semantic-generation-patch.mjs
      ./semantic-check.mjs
      ./semantic-control.test.mjs
      ./semantic-live.mjs
      ./jev-agent
      ./jev-playground
    ];
  };
  npmDepsHash = "sha256-PSB7K1CWH22c9muaBj/TQ6QEw9bdu8wAeCeROQshhHk=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/pi-runtime" "$out/bin"
    # Fabric filters type correctness outside Schema enforce (which disables Jev).
    # Keep its own checker, but require strict TypeScript before execution.
    substituteInPlace node_modules/pi-fabric/dist/chunks/chunk-N5GUXC6F.js \
      --replace-fail 'strict: false' 'strict: true' \
      --replace-fail 'noImplicitAny: false' 'noImplicitAny: true' \
      --replace-fail 'strictNullChecks: false' 'strictNullChecks: true' \
      --replace-fail 'strictFunctionTypes: false' 'strictFunctionTypes: true' \
      --replace-fail 'strictBindCallApply: false' 'strictBindCallApply: true' \
      --replace-fail 'strictPropertyInitialization: false' 'strictPropertyInitialization: true' \
      --replace-fail 'alwaysStrict: false' 'alwaysStrict: true' \
      --replace-fail 'noImplicitThis: false' 'noImplicitThis: true' \
      --replace-fail 'useUnknownInCatchVariables: false' 'useUnknownInCatchVariables: true' \
      --replace-fail 'includeTypeCorrectness || !TYPE_CORRECTNESS_CODES.has(diagnostic.code)' 'true'
    node semantic-fabric-patch.mjs node_modules/pi-fabric/dist
    node semantic-control-patch.mjs node_modules/pi-fabric/dist
    node semantic-generation-patch.mjs node_modules
    node semantic-trace.test.mjs
    node semantic-control.test.mjs
    node jev-agent/fixtures.test.mjs
    node jev-agent/tasks.test.mjs
    node jev-playground/playground.test.mjs
    cp -R node_modules package.json guidance.md validate.mjs skill semantic-trace.ts semantic-trace.test.mjs semantic-state.ts semantic-policy.ts semantic-controller.ts semantic-extension.ts semantic-check.mjs semantic-control.test.mjs semantic-live.mjs jev-agent jev-playground "$out/lib/pi-runtime/"
    install -Dm644 credential.py "$out/lib/pi-runtime/credential.py"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pi-jev-playground" \
      --add-flags "$out/lib/pi-runtime/jev-playground/cli.mjs" \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt
    makeWrapper ${python3}/bin/python3 "$out/bin/pi-jev-credential" \
      --add-flags "$out/lib/pi-runtime/credential.py"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pi" \
      --add-flags "$out/lib/pi-runtime/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          ripgrep
          git
          bash
          typescript-language-server
          nixd
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --run 'unset JEV_KEY TYPESAFE_API_KEY OPENAI_API_KEY'
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pi-validate" \
      --add-flags "$out/lib/pi-runtime/validate.mjs" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          ripgrep
          git
          bash
          typescript-language-server
          nixd
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --run 'unset JEV_KEY TYPESAFE_API_KEY OPENAI_API_KEY'
    runHook postInstall
  '';
  meta = {
    description = "Upstream Pi with checked Fabric, incremental semantics and finite Jev-only coding mode";
    mainProgram = "pi";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
