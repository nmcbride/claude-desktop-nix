{
  description = "Nix flake for the official Claude desktop app on Linux (Chat, Cowork, Claude Code)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # claude-desktop is unfree; scope the allowance to just this package so
      # `nix build` works without --impure and without relaxing unfree globally.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-desktop" ];
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          claude-desktop = pkgs.callPackage ./package.nix { };
        in
        {
          inherit claude-desktop;
          default = claude-desktop;
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/claude-desktop";
          meta.description = "Run the Claude desktop app";
        };
      });

      overlays.default = final: prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      nixosModules.default = import ./nixos-module.nix self;

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
