{
  description = "UGA Manufacturing Living Labs OPKSSH setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "uga-living-labs-opkssh-setup";
          version = "0.1.0";
          src = self;

          installPhase = ''
            runHook preInstall

            install -Dm755 client_setup $out/bin/uga-opkssh-client-setup
            install -Dm755 server_setup $out/bin/uga-opkssh-server-setup
            install -Dm755 scripts/living_labs_auth_sync $out/bin/living-labs-auth-sync
            install -Dm755 scripts/factory_ssh_no_shell $out/bin/factory-ssh-no-shell

            install -Dm644 README.md $out/share/doc/uga-living-labs-opkssh/README.md
            install -Dm644 docs/architecture.md $out/share/doc/uga-living-labs-opkssh/architecture.md
            install -Dm644 examples/entra_groups.tsv $out/share/uga-living-labs-opkssh/examples/entra_groups.tsv
            install -Dm644 examples/entra_roles.tsv $out/share/uga-living-labs-opkssh/examples/entra_roles.tsv
            install -Dm644 examples/email_users.tsv $out/share/uga-living-labs-opkssh/examples/email_users.tsv

            runHook postInstall
          '';
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/uga-opkssh-client-setup";
        };

        formatter = pkgs.nixpkgs-fmt;

        checks.package = self.packages.${system}.default;
      }) // {
        nixosModules.default = self.nixosModules.living-labs;
        nixosModules.living-labs = import ./nixos/living-labs.nix;
      };
}
