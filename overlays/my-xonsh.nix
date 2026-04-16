final: prev: {
  python-env = prev.python313.withPackages (
    ps: with ps; [
      xonsh
      prompt-toolkit
      requests
      httpx
      xontrib-jedi
      wcmatch
      pyclip
      xontrib-prompt-starship
      plumbum
      libtmux
      rich
      duckdb
      pyarrow
      protobuf

      # Build Polars without jemalloc
      #(ps.polars.overrideAttrs (old: {
      #  env = (old.env or { }) // {
      #    CARGO_BUILD_FLAGS = #"--no-default-features --features=lazy,parquet,csv";
      #  };
      #}))

      jinja2-time
      cookiecutter
      copier
      copier-templates-extensions
    ]
  );

  xonsh = final.python-env;
}
