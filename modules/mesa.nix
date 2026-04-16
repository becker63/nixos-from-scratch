{ mesa-pinned, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      mesa = mesa-pinned.legacyPackages.${prev.system}.mesa;
      mesa_drivers = mesa-pinned.legacyPackages.${prev.system}.mesa.drivers;
    })
  ];
}
