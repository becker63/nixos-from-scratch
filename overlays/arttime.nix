{ arttime-src }:

final: prev: {
  arttime = prev.stdenv.mkDerivation rec {
    pname = "arttime";
    version = "git";
    src = arttime-src;

    nativeBuildInputs = [ prev.makeWrapper ];
    buildInputs = [ prev.zsh ];

    installPhase = ''
      runHook preInstall

      # Copy upstream scripts into share dir
      mkdir -p $out/share/arttime/bin
      cp bin/arttime $out/share/arttime/bin/
      cp bin/artprint $out/share/arttime/bin/

      # Copy data
      mkdir -p $out/share/arttime/{src,keypoems,doc,textart}
      cp share/arttime/src/* $out/share/arttime/src/
      cp share/arttime/keypoems/* $out/share/arttime/keypoems/
      cp share/arttime/doc/* $out/share/arttime/doc/
      cp share/arttime/textart/* $out/share/arttime/textart/

      mkdir -p $out/share/man/man1
      cp share/man/man1/* $out/share/man/man1/

      mkdir -p $out/share/zsh/functions
      cp share/zsh/functions/* $out/share/zsh/functions/

      # Wrappers that force nixpkgs' zsh to execute the real scripts
      mkdir -p $out/bin
      makeWrapper ${prev.zsh}/bin/zsh $out/bin/arttime \
        --add-flags "-c $out/share/arttime/bin/arttime"
      makeWrapper ${prev.zsh}/bin/zsh $out/bin/artprint \
        --add-flags "-c $out/share/arttime/bin/artprint"

      runHook postInstall
    '';
  };
}
