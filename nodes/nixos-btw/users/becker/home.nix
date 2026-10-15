{ modules', ... }:

{
  imports = [
    modules'.desktop-profile
    modules'.pi
    modules'.packages
    modules'.opencode
    modules'.factory
    modules'.research-visualizer
  ];
}
