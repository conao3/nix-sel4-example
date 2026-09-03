{
  description = "A starting point for building seL4 Microkit systems with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-sel4.url = "github:conao3/nix-sel4";
    nix-sel4.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, nix-sel4, ... }:
    let
      # The machine you build on. Building for a seL4 target does not require
      # that target's hardware; QEMU emulates it.
      system = "x86_64-linux";

      # The seL4 target. `nix run` works for the three QEMU boards; every other
      # board in nix-sel4's lib/boards.nix builds an image you flash yourself.
      board = "qemu_virt_aarch64";

      # debug keeps the kernel's console output, which is what makes
      # microkit_dbg_puts visible. Switch to release once you have a driver.
      config = "debug";

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-sel4.overlays.default ];
      };

      inherit (pkgs) microkitTools;

      # One protection domain, built from every source file under ./src/main.
      main = microkitTools.buildProtectionDomain {
        name = "main";
        inherit board config;
        src = ./src/main;
      };

      # The system description, written as Nix rather than XML. Sizes and
      # addresses are plain integers.
      sel4System = microkitTools.buildSystem {
        name = "example";
        inherit board config;

        system = microkitTools.mkSystemDescription {
          protectionDomains.main = {
            priority = 100;
            programImage = main.programImage;
          };
        };

        pds.${main.programImage} = main;
      };
    in
    {
      packages.${system} = {
        # nix run . boots the system under QEMU. Quit with Ctrl-A then x.
        default = sel4System.qemu;

        # nix build .#image gives you loader.img to flash or to boot yourself.
        image = sel4System.image;

        # nix build .#report shows how the kernel objects and memory were
        # allocated.
        report = sel4System.report;
      };

      # nix flake check boots the system and fails if the greeting is missing.
      checks.${system}.boots = pkgs.runCommand "example-boots" { } ''
        timeout -s KILL 120 ${sel4System.qemu}/bin/example-qemu < /dev/null > console.log 2>&1 || true

        if ! grep -qF "hello from a Nix-built seL4 system" console.log; then
          echo "the protection domain did not reach its init function:" >&2
          cat console.log >&2
          exit 1
        fi

        cp console.log $out
      '';

      devShells.${system}.default = nix-sel4.devShells.${system}.default;

      formatter.${system} = pkgs.nixfmt;
    };
}
