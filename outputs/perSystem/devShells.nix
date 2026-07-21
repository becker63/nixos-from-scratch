{ nodes, ... }:

{
  default = nodes.nixos-btw.pkgs.mkShell {
    packages = [ nodes.nixos-btw.pkgs.python-env ];
  };
}
