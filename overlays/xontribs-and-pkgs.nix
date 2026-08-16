{
  xontrib-jedi-src,
  xontrib-prompt-starship-src,
  copier-templates-extensions-src,
}:

final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (ps-final: ps-prev: {

      xontrib-jedi = ps-final.buildPythonPackage rec {
        pname = "xontrib-jedi";
        version = "0.2.0";
        pyproject = true;
        src = xontrib-jedi-src;

        build-system = [ ps-final.poetry-core ];
        propagatedBuildInputs = [ ps-final.jedi ps-final.xonsh ];
      };

      xontrib-prompt-starship = ps-final.buildPythonPackage {
        pname = "xontrib-prompt-starship";
        version = "0.3.8";
        src = xontrib-prompt-starship-src;
        doCheck = false;
        pyproject = true;

        build-system = [ ps-final.setuptools ps-final.wheel ];
        propagatedBuildInputs = [ ps-final.xonsh ];
      };

      copier-templates-extensions = ps-final.buildPythonPackage rec {
        # The Python distribution is singular; the plural attribute name is
        # retained below for compatibility with the existing Xonsh overlay.
        pname = "copier-template-extensions";
        # PDM derives the wheel version from the source; keep this valid PEP
        # 440 metadata so current nixpkgs' Python checks can compare it.
        version = "0.3.3";
        src = copier-templates-extensions-src;

        pyproject = true;
        build-system = [ ps-final.pdm-backend ];
        propagatedBuildInputs = [ ps-final.jinja2 ps-final.copier ];
        doCheck = false;
      };

    })
  ];
}
