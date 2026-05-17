{
  description: "Stoa - Local-first decentralized collaboration platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        rustVersion = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ "aarch64-linux-android" "armv7-linux-androideabi" "x86_64-linux-android" ];
        };

        runtimeLibs = with pkgs; [
          libglvnd
          libxkbcommon
          wayland
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          # Tauri 2.0 Dependencies
          webkit2gtk_4_1
          gtk3
          cairo
          gdk-pixbuf
          glib
          dbus
          openssl_3
          librsvg
          libappindicator-gtk3
          libsoup_3
        ];

        nativeBuildInputs = with pkgs; [
          pkg-config
          gobject-introspection
          cargo
          rustVersion
          nodejs_20
          python3
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          inherit nativeBuildInputs;
          buildInputs = runtimeLibs;

          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath runtimeLibs}:$LD_LIBRARY_PATH
            export WEBKIT_DISABLE_COMPOSITING_MODE=1
            echo "--- Stoa Development Environment ---"
            echo "Rust: $(rustc --version)"
            echo "Node: $(node --version)"
            echo "Ready to build! Run 'npm run tauri dev' to start."
          '';
        };
      }
    );
}
