{ lib
, buildPythonApplication
, poetry-core
, # Runtime deps from pythonlib/pyproject.toml. All available in
  # nixpkgs as of release-26.05.
  rich-click
, rich
, requests
, orjson
, browserforge
, playwright
, pyyaml
, platformdirs
, numpy
, ua-parser
, typing-extensions
, screeninfo
, lxml
, language-tags
, pysocks
, inquirer
, makeWrapper
, camoufox-bin
}:

buildPythonApplication rec {
  pname = "camoufox-python";
  version = "0.5.2";
  pyproject = true;

  # The python lib lives in pythonlib/ inside the repo. cleanSource
  # would normally strip .git etc., but the build only reads files
  # listed in pyproject.toml, so an unfiltered path is fine.
  src = ../pythonlib;

  build-system = [ poetry-core ];

  dependencies = [
    rich-click
    rich
    requests
    orjson
    browserforge
    playwright
    pyyaml
    platformdirs
    numpy
    ua-parser
    typing-extensions
    screeninfo
    lxml
    language-tags
    pysocks
    inquirer
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Wire the python lib at the nix-store browser dist. The launch_path()
  # and camoufox_path() helpers in pkgman.py honour these env vars
  # (patched in the flake branch), so user code that does
  # `Camoufox()` without `executable_path` still launches the
  # FHS-wrapped binary, and `get_path("fonts")` resolves into the
  # unpacked dist for fontconfig setup.
  postInstall = ''
    for bin in $out/bin/camoufox $out/bin/camoufox-server; do
      wrapProgram "$bin" \
        --set-default CAMOUFOX_EXECUTABLE_PATH ${camoufox-bin}/share/camoufox/camoufox-bin \
        --set-default CAMOUFOX_DIST_PATH ${camoufox-bin.passthru.unpacked}
    done
  '';

  # Lib pulls in network at import time for version checks otherwise;
  # skip its test suite — we exercise it end-to-end via the home-manager
  # verify step instead.
  doCheck = false;

  pythonImportsCheck = [ "camoufox" "camoufox.sync_api" "camoufox.server_main" ];

  passthru = {
    inherit camoufox-bin;
  };

  meta = with lib; {
    description = "Camoufox python library + CLI (wired to a nix-managed browser binary)";
    homepage = "https://camoufox.com/python";
    license = licenses.mit;
    mainProgram = "camoufox";
  };
}
