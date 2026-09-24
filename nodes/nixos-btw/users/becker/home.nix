{ modules', ... }:

{
  imports = [
    modules'.base
    modules'.desktop
    modules'.packages
    modules'.opencode
    modules'.factory
  ];
}
