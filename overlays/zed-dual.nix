final: prev: {
  zed =
    prev.runCommand "zed"
      {
        buildInputs = [ prev.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${prev.zed-editor.fhs}/bin/zeditor $out/bin/zed
      '';

  zed_raw =
    prev.runCommand "zed_raw"
      {
        buildInputs = [ prev.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${prev.zed-editor}/bin/zeditor $out/bin/zed_raw
      '';
}
