final: prev: {
  haskellPackages = prev.haskellPackages.override {
    overrides = self: super: {
      hascard = let
        base = prev.haskell.lib.overrideCabal
          (super.hascard or (self.callHackageDirect {
            pkg = "hascard";
            ver = "0.6.0.2";
            sha256 = "sha256-7MepVFNGcEwnXo/tulH/Ko84QoBDY2u7j+Vn7/MmU+U=";
          } { })) (old: { jailbreak = true; });
      in base.overrideAttrs
      (old: { meta = (old.meta or { }) // { broken = false; }; });
    };
  };
}
