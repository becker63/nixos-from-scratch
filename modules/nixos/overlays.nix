{ lib', ... }:

{
  nixpkgs.overlays = lib'.overlays;
}
