{ modules', ... }:

{
  imports = [
    modules'.base
    modules'.desktop
    modules'.pi
    modules'.packages
    modules'.opencode
    modules'.factory
    modules'.research-visualizer
  ];
}
