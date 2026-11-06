{
  lib,
  melpaBuild,
  stdenv,
  zig_0_17,
  emacs,
  xcbuild,
}:
let
  zig = zig_0_17;

  pname = "ghostel";

  version = builtins.head (
    builtins.match ''.*pub const version = "([^"]+)";.*'' (builtins.readFile ../src/version.zig)
  );

  # Separate sources for the module and the Lisp package, so editing Lisp
  # does not recompile the module (and libghostty with it), and vice versa.
  moduleSrc = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../symbols.map
      ../src
      ../vendor
    ];
  };

  lispSrc = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../lisp
      ../etc
    ];
  };

  module = stdenv.mkDerivation (finalAttrs: {
    inherit pname version;
    src = moduleSrc;

    # This hash covers the dependencies pinned in build.zig.zon and must be
    # updated whenever they change: set it to lib.fakeHash, run
    # `nix build .#ghostel-module.deps`, and copy the hash Nix reports.
    # fetchAll makes the dependency tree platform-independent, so a single
    # hash covers all systems.
    deps = zig.fetchDeps {
      inherit (finalAttrs) src pname version;
      fetchAll = true;
      hash = "sha256-Kt3r1B/5kgjMO89gih/87oEtuWmby9NB6oQp5t0vUYw=";
    };

    nativeBuildInputs = [ zig ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ xcbuild ];

    env.EMACS_INCLUDE_DIR = "${emacs}/include";

    dontSetZigDefaultFlags = true;

    doCheck = true;

    zigCheckFlags = [
      "-Dcpu=baseline"
      # See https://github.com/ghostty-org/ghostty/blob/main/PACKAGING.md#build-options
      "-Doptimize=ReleaseFast"
    ];

    zigBuildFlags = finalAttrs.zigCheckFlags;

    postConfigure = ''
      cp -rLT ${finalAttrs.deps} "$ZIG_GLOBAL_CACHE_DIR/p"
      chmod -R u+w "$ZIG_GLOBAL_CACHE_DIR/p"
    '';
  });

  libExt = stdenv.hostPlatform.extensions.sharedLibrary;
in
melpaBuild {
  inherit pname version;
  src = lispSrc;

  files = ''
    (:defaults "etc" "ghostel-module${libExt}" "ghostel-module.version")
  '';

  preBuild = ''
    install ${module}/ghostel-module${libExt} ghostel-module${libExt}
    install --mode=444 ${module}/ghostel-module.version ghostel-module.version
  '';

  passthru = {
    inherit module;
  };

  meta = {
    homepage = "https://github.com/dakra/ghostel";
    description = "Terminal emulator powered by libghostty";
    license = lib.licenses.gpl3Plus;
  };
}
