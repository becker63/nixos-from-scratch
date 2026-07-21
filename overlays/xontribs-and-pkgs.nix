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
        version = "git";
        pyproject = true;
        src = xontrib-jedi-src;

        build-system = [ ps-final.poetry-core ];
        propagatedBuildInputs = [ ps-final.jedi ps-final.xonsh ];
      };

      xontrib-prompt-starship = ps-final.buildPythonPackage {
        pname = "xontrib-prompt-starship";
        version = "git";
        src = xontrib-prompt-starship-src;
        doCheck = false;
        pyproject = true;

        build-system = [ ps-final.setuptools ps-final.wheel ];
        propagatedBuildInputs = [ ps-final.xonsh ];
      };

      copier-templates-extensions = ps-final.buildPythonPackage rec {
        pname = "copier-templates-extensions";
        version = "git";
        src = copier-templates-extensions-src;

        pyproject = true;
        build-system = [ ps-final.pdm-backend ];
        propagatedBuildInputs = [ ps-final.jinja2 ps-final.copier ];
        doCheck = false;
      };

    })
  ];
}
