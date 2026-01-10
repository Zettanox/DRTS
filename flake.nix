{
  description = "Stoa - Collaborative file sharing and messaging app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # Android SDK configuration - include all common platform versions
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "11.0";
          platformToolsVersion = "35.0.1";
          buildToolsVersions = [ "30.0.3" "33.0.2" "34.0.0" "35.0.0" ];
          platformVersions = [ "31" "32" "33" "34" "35" "36" ];
          abiVersions = [ "arm64-v8a" "x86_64" ];
          includeEmulator = false;
          includeNDK = true;
          ndkVersions = [ "27.0.12077973" ];
          cmakeVersions = [ "3.22.1" ];
        };

        androidSdk = androidComposition.androidsdk;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Flutter SDK
            flutter
            dart

            # Android development
            androidSdk
            jdk17

            # Linux desktop dependencies
            clang
            cmake
            ninja
            pkg-config
            gtk3
            glib
            pcre2
            libepoxy
            libGL
            sysprof

            # Additional tools
            git
            curl
            unzip
            xz
          ];

          # Environment variables
          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
          
          # Fix for Flutter Linux builds
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.libGL
            pkgs.libepoxy
          ];

          shellHook = ''
            echo ""
            echo "🏛️  Stoa Development Environment"
            echo "================================="
            echo ""
            flutter --version | head -1
            echo ""
            echo "Commands:"
            echo "  flutter run -d linux    - Run on Linux desktop"
            echo "  flutter run -d chrome   - Run in Chrome browser"
            echo "  flutter build linux     - Build Linux binary"
            echo "  flutter build apk       - Build Android APK"
            echo ""
            
            # Accept Android licenses silently
            yes | ${androidSdk}/libexec/android-sdk/cmdline-tools/latest/bin/sdkmanager --licenses > /dev/null 2>&1 || true
          '';
        };
      }
    );
}
