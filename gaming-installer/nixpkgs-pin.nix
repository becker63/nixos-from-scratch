# Snapshot of the repository's existing nixpkgs pin. No input updates.
builtins.fetchTree {
  type = "github";
  owner = "NixOS";
  repo = "nixpkgs";
  rev = "2fcb964de67fcf60b43471c55d5d99e61a9ccb5a";
  narHash = "sha256-RzPPiWeUtuvymnpuEWsdtzli5w4kjZs49FqEs3/1u+I=";
}
