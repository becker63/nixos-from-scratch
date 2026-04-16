final: prev: {
  xonsh = final.python-env;
  scripts = prev.stdenv.mkDerivation {
    pname = "scripts";
    version = "0.1.0";
    src = ./../scripts;

    nativeBuildInputs = [ prev.makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin
      for f in $src/*.py; do
        name=$(basename "$f" .py)
        cp "$f" "$out/bin/$name.py"
        chmod +x "$out/bin/$name.py"

        makeWrapper ${final.python-env}/bin/python $out/bin/$name \
          --add-flags $out/bin/$name.py
      done
    '';
  };
}
