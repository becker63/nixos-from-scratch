{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "attune-ratatui-workbench";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../events.jsonl
      ../visualizations.jsonl
      ../rust/Cargo.toml
      ../rust/Cargo.lock
      ../rust/src
    ];
  };
  cargoRoot = "rust";
  buildAndTestSubdir = "rust";
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Ratatui observer for Attune experiments and Codex App Server";
    platforms = lib.platforms.linux;
  };
}
