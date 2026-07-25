{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig = {
      url = "github:silversquirl/zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    clap-devtools = {
      url = "git+https://codeberg.org/kengo/clap-devtools";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      zig,
      clap-devtools,
      ...
    }:
    let
      forAllSystems = f: builtins.mapAttrs f nixpkgs.legacyPackages;
    in
    {
      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShellNoCC {
            packages = [
              zig.packages.${system}.default
              zig.packages.${system}.default.zls
              clap-devtools.packages.${system}.clap-info
              clap-devtools.packages.${system}.clap-validator
            ];
          };
        }
      );
    };
}
