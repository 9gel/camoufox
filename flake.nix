{
  description = "Camoufox: anti-detect Firefox build, packaged for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };

        camoufox-bin = pkgs.callPackage ./nix/camoufox-bin.nix { };

        camoufox-python = pkgs.python3Packages.callPackage ./nix/camoufox-python.nix {
          inherit camoufox-bin;
        };

        # `default` is the user-facing entry point: pulls in both the
        # python CLI (`camoufox`, with CAMOUFOX_EXECUTABLE_PATH set) and
        # the patched browser binary. Installing this one package is
        # enough to replace `pip install camoufox && camoufox fetch`.
        camoufox = pkgs.buildEnv {
          name = "camoufox-${camoufox-bin.version}";
          paths = [ camoufox-python camoufox-bin ];
          # buildEnv defaults symlink everything; the python wrapper
          # owns the `camoufox` name in bin/, the binary's wrapper owns
          # nothing user-facing because both live under share/camoufox.
          ignoreCollisions = true;
          meta = camoufox-bin.meta // {
            description = "Camoufox python lib + browser binary, wired together";
          };
        };
      in {
        packages = {
          inherit camoufox-bin camoufox-python camoufox;
          default = camoufox;
        };

        apps.default = {
          type = "app";
          program = "${camoufox}/bin/camoufox";
        };

        devShells.default = pkgs.mkShell {
          packages = [ camoufox pkgs.python3 ];
          shellHook = ''
            export CAMOUFOX_EXECUTABLE_PATH=${camoufox-bin}/share/camoufox/camoufox-bin
          '';
        };
      });
}
