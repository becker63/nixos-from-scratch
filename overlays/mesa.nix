# overlays/mesa-pinned.nix
{ mesa-pinned }:
final: prev: {
  mesa = mesa-pinned.legacyPackages.${prev.system}.mesa;
  mesa_drivers = mesa-pinned.legacyPackages.${prev.system}.mesa.drivers;
}
