{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zig = {
      url = "github:silversquirl/zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zls = {
      url = "github:zigtools/zls";
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
      zls,
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
              zig.packages.${system}.nightly
              zls.packages.${system}.zls
              clap-devtools.packages.${system}.clap-info
              clap-devtools.packages.${system}.clap-validator
            ];
          };
        }
      );
    };
}
