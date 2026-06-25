{ lib
, stdenv
, fetchurl
, buildFHSEnv
, makeWrapper
, unzip
, runtimeShell
, # Audio + virtual-display tools wired into the FHS env so camoufox
  # can spawn Xvfb (via Camoufox(headless='virtual')) without the user
  # installing extra packages.
  xvfb-run
, coreutils
, # All runtime libraries Firefox needs. Mirrors nixpkgs' firefox FHS env.
  alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, curl
, dbus
, dbus-glib
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, glibc
, gtk3
, libdrm
, libGL
, libnotify
, libpulseaudio
, libva
, libxkbcommon
, libdbusmenu
, libffi
, mesa
, nspr
, nss
, pango
, pciutils
, pipewire
, libxcb
, xorg
, zlib
, ffmpeg
}:

let
  tag = "v150.0.2-beta.25";
  assetSuffix = "alpha.26";
  upstreamVersion = "150.0.2";
  version = "${upstreamVersion}-${assetSuffix}";

  src = fetchurl {
    url = "https://github.com/daijro/camoufox/releases/download/${tag}/camoufox-${upstreamVersion}-${assetSuffix}-lin.x86_64.zip";
    sha256 = "02si1xkqh2sb99c58b7p151m76ii3x2kdvzy2qvh4h9c1j5vjimi";
  };

  # Just unpack the zip — no ELF patching. The binary expects to find
  # Firefox-shaped /usr/lib/* layout, which buildFHSEnv supplies.
  unpacked = stdenv.mkDerivation {
    pname = "camoufox-unpacked";
    inherit version src;
    nativeBuildInputs = [ unzip ];
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    unpackPhase = ''
      mkdir -p $out
      unzip -q "$src" -d "$out"
      chmod +x $out/camoufox-bin $out/camoufox || true
    '';
  };

  # FHS env with every lib Firefox needs at runtime. The unmodified
  # camoufox-bin runs inside it, finds its libs via standard /usr/lib
  # lookup, and skips the whole autoPatchelf can-of-worms.
  fhs = buildFHSEnv {
    name = "camoufox";

    targetPkgs = pkgs: with pkgs; [
      # GUI / X
      gtk3
      glib
      atk
      cairo
      pango
      gdk-pixbuf
      at-spi2-atk
      at-spi2-core
      dbus
      dbus-glib
      libdbusmenu
      libnotify
      libxkbcommon
      fontconfig
      freetype
      expat
      libxcb
      xorg.libX11
      xorg.libXScrnSaver
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXt
      xorg.libXtst
      # GL / video / audio
      libGL
      libdrm
      mesa
      libva
      ffmpeg
      alsa-lib
      libpulseaudio
      pipewire
      # System
      cups
      curl
      glibc
      libffi
      nspr
      nss
      pciutils
      zlib
      # Virtual display (Camoufox python lib spawns this for headless='virtual')
      xvfb-run
      xorg.xorgserver
      coreutils
    ];

    runScript = "${unpacked}/camoufox-bin";

    # Preserve the user's HOME / DISPLAY / etc. and ensure Playwright
    # passes its CLI args through unchanged.
    extraInstallCommands = "";

    meta = {
      description = "Camoufox: anti-detect Firefox build (prebuilt binary, FHS-wrapped)";
      homepage = "https://camoufox.com";
      license = lib.licenses.mpl20;
      platforms = [ "x86_64-linux" ];
      mainProgram = "camoufox";
    };
  };

in
stdenv.mkDerivation {
  pname = "camoufox-bin";
  inherit version;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/camoufox

    # Expose the FHS-wrapped launcher as `camoufox`.
    ln -s ${fhs}/bin/camoufox $out/bin/camoufox

    # Mirror the unpacked dist under $out/share/camoufox so consumers
    # (e.g. CAMOUFOX_EXECUTABLE_PATH) have a stable, library-style
    # pointer to the raw binary. Path resolves inside the FHS chroot too.
    ln -s ${unpacked} $out/share/camoufox/dist
    ln -s ${fhs}/bin/camoufox $out/share/camoufox/camoufox-bin

    runHook postInstall
  '';

  passthru = {
    inherit tag upstreamVersion assetSuffix unpacked fhs;
    # Python wrapper reads this to set Camoufox(executable_path=...)
    # without the user passing it explicitly.
    executable = "${placeholder "out"}/share/camoufox/camoufox-bin";
  };

  meta = {
    description = "Camoufox: anti-detect Firefox build (FHS-wrapped binary)";
    homepage = "https://camoufox.com";
    license = lib.licenses.mpl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "camoufox";
  };
}
