{ lib
, rustPlatform
, pkg-config
, makeWrapper
, dbus
, openssl
, libxkbcommon
, wayland
, libGL
, xorg
}:

rustPlatform.buildRustPackage {
  pname = "cursor-dialog-daemon";
  version = "0.3.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    dbus
    openssl
    libxkbcommon
    wayland
    libGL
    xorg.libX11
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXi
  ];

  # egui/eframe needs these at runtime
  postInstall = ''
    wrapProgram $out/bin/cursor-dialog-daemon \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        libxkbcommon
        wayland
        libGL
        xorg.libX11
      ]}"
    wrapProgram $out/bin/cursor-dialog-cli \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        libxkbcommon
        wayland
        libGL
        xorg.libX11
      ]}"
  '';

  meta = with lib; {
    description = "D-Bus daemon for Cursor agent interactive dialogs";
    homepage = "https://github.com/e421/nixos-cursor";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}

