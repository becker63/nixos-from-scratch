final: prev: {
  alacritty = prev.alacritty.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/alacritty-copy-buffer.patch
      ../patches/alacritty-gutter-animation.patch
    ];
  });
}
