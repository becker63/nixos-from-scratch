{ ... }:
{
  imports = [ ./host.nix ];
  _module.args.desktopSource = ./config;
  _module.args.wallpaper = ./wallpaper.jpg;
  _module.args.nixpkgsSource = <nixpkgs>;
  _module.args.jovianSource = (import ./jovian-pin.nix).outPath;
}
