{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "attune-ratatui-workbench";
  version = "0.1.0";
  src = ../.;
  cargoRoot = "rust";
  buildAndTestSubdir = "rust";
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Ratatui observer for Attune experiments and Codex App Server";
    platforms = lib.platforms.linux;
  };
}
