{
  lib,
  stdenv,
  fetchurl,
  # build tooling
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeWrapper,
  # link/runtime libraries (NEEDED by the vendored ELF binaries)
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  pango,
  libdrm,
  libgbm,
  libxkbcommon,
  nspr,
  nss,
  systemd,
  util-linux,
  libseccomp,
  libcap_ng,
  libX11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxtst,
  # dlopen'd at runtime
  libglvnd,
  libnotify,
  libsecret,
  libayatana-appindicator,
  pulseaudio,
  pipewire,
  # runtime PATH deps
  qemu,
  xdg-utils,
  # options
  commandLineArgs ? "",
  # Force Chromium's setuid sandbox off. On stock NixOS the unprivileged
  # user-namespace sandbox works, so the default keeps the sandbox on.
  disableSandbox ? false,
}:

let
  pname = "claude-desktop";
  version = "1.22209.3";

  # Official Anthropic apt repo:
  #   https://downloads.claude.ai/claude-desktop/apt/stable
  baseUrl = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop";
  sources = {
    x86_64-linux = fetchurl {
      url = "${baseUrl}/claude-desktop_${version}_amd64.deb";
      hash = "sha256-1Cf0askjPbxNikQaYC8J91C4pfBdH8egAoXXps4HZVw=";
    };
    aarch64-linux = fetchurl {
      url = "${baseUrl}/claude-desktop_${version}_arm64.deb";
      hash = "sha256-Vcy0eLItcbRuZpWC565Nb0T8bf8LPVFakWMEnatANLI=";
    };
  };

  src =
    sources.${stdenv.hostPlatform.system}
      or (throw "claude-desktop: unsupported system ${stdenv.hostPlatform.system}");

  # Libraries the app dlopen's at runtime (not in the ELF NEEDED lists, so
  # autoPatchelfHook wouldn't otherwise put them on the rpath).
  runtimeLibs = [
    libglvnd
    libnotify
    libsecret
    libayatana-appindicator
    pulseaudio
    pipewire
  ];
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    pango
    libdrm
    libgbm
    libxkbcommon
    nspr
    nss
    systemd # libudev.so.1
    util-linux # libuuid.so.1
    libseccomp # virtiofsd
    libcap_ng # virtiofsd
    libX11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxtst
    stdenv.cc.cc.lib # libstdc++.so.6, libgcc_s.so.1
  ]
  ++ runtimeLibs;

  # autoPatchelfHook adds these to the rpath of every patched binary.
  runtimeDependencies = runtimeLibs;

  # We build our own wrapper below and want the GApps environment folded in.
  dontWrapGApps = true;

  # The vendored Electron ships libEGL/libGLESv2/libffmpeg/libvulkan next to
  # the main binary; autoPatchelfHook resolves those from $out. A couple of
  # GPU/vulkan sonames are only present when a real driver is installed, so
  # don't fail the build over them.
  autoPatchelfIgnoreMissingDeps = [
    "libvulkan.so.1"
  ];

  unpackPhase = ''
    runHook preUnpack
    # Pipe through tar (as non-root) rather than `dpkg-deb -x`, which tries to
    # restore chrome-sandbox's setuid bit and fails in the build sandbox.
    dpkg-deb --fsys-tarfile "$src" | tar --extract --no-same-permissions --no-same-owner
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/share"
    # The Electron app tree, verbatim (resources/, locales/, *.pak, the
    # vendored .so files, the bundled electron binary, chrome-sandbox, the
    # Cowork helpers + microVM image).
    cp -r usr/lib/claude-desktop "$out/lib/claude-desktop"

    # Desktop entry + icons.
    cp -r usr/share/applications "$out/share/applications"
    cp -r usr/share/icons "$out/share/icons"

    runHook postInstall
  '';

  preFixup =
    let
      # Static, build-time-known flags, prepended verbatim.
      staticFlags =
        lib.optionalString disableSandbox "--no-sandbox "
        + lib.optionalString (commandLineArgs != "") "${commandLineArgs} ";
      # Wayland flags must reach the wrapper *literally* so NIXOS_OZONE_WL is
      # evaluated at run time, not at build time — hence the ''$ escaping
      # (same idiom as nixpkgs' other Electron apps).
      waylandFlags = ''\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}'';
    in
    ''
      makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
        "''${gappsWrapperArgs[@]}" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib" \
        --prefix PATH : "${
          lib.makeBinPath [
            qemu
            xdg-utils
          ]
        }" \
        --add-flags "${staticFlags}${waylandFlags}"
    '';

  # chrome-sandbox can't be setuid in the store; Chromium uses the
  # user-namespace sandbox on NixOS instead.
  meta = {
    description = "Official Claude desktop app for Linux (Chat, Cowork, and Claude Code)";
    homepage = "https://claude.ai/download";
    downloadPage = "https://code.claude.com/docs/en/desktop-linux";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "claude-desktop";
  };
}
