{ xontrib-jedi-src, xontrib-prompt-starship-src, xontrib-output-search-src
, tokenize-output-src, copier-templates-extensions-src }:

final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (ps-final: ps-prev: {

      tokenize-output = ps-final.buildPythonPackage {
        pname = "tokenize-output";
        version = "git";
        pyproject = true;
        src = tokenize-output-src;

        build-system = [ ps-final.setuptools ps-final.wheel ];
        propagatedBuildInputs = [ ps-final.demjson3 ];
      };

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

      /* xontrib-output-search = ps-final.buildPythonPackage {
           pname = "xontrib-output-search";
           version = "git";
           src = xontrib-output-search-src;
           doCheck = false;
           pyproject = true;

           build-system = [ ps-final.setuptools ps-final.wheel ];
           propagatedBuildInputs = [ ps-final.xonsh ps-final.tokenize-output ];
           # This patch does nothing, I just found it interesting that nix lets me do this and I would like to actually modify the tokenizer later to filter out non ascii chars as I was trying to do
           patches = [ ./xontrib-output-search-fallback.patch ];
           patchFlags = [ "-p1" "--verbose" ];

           postPatch = ''
             echo ">>> after patch, checking for _is_ascii"
             grep -n "_is_ascii" xontrib/output_search.py || true
           '';

         };
      */

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
