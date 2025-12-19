# Nix derivation for cursor-proxy
#
# Build with:
#   nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
#
# Or use in a flake:
#   cursor-proxy = pkgs.callPackage ./tools/proxy-test/cursor-proxy { };

{ lib
, rustPlatform
, pkg-config
, openssl
}:

rustPlatform.buildRustPackage rec {
  pname = "cursor-proxy";
  version = "0.1.0";
  
  src = ./.;
  
  cargoLock = {
    lockFile = ./Cargo.lock;
  };
  
  nativeBuildInputs = [
    pkg-config
  ];
  
  buildInputs = [
    openssl
  ];
  
  # Skip tests for now (they may require network)
  doCheck = false;
  
  meta = with lib; {
    description = "Transparent proxy for Cursor AI traffic interception and context injection";
    homepage = "https://github.com/e421/nixos-cursor";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}

