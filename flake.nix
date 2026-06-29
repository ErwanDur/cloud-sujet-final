{
  description = "Cloud TP Finale — IaC AWS (Terraform + Ansible)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, git-hooks }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      checks.${system}.pre-commit-check = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          gitleaks.enable = true;
          terraform-format.enable = true;
          commitlint = {
            enable = true;
            name = "commitlint";
            stages = [ "commit-msg" ];
            entry = "${pkgs.nodePackages."@commitlint/cli"}/bin/commitlint --edit";
            language = "system";
            pass_filenames = false;
          };
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        inherit (self.checks.${system}.pre-commit-check) shellHook;
        packages = with pkgs; [
          terraform
          awscli2
          ansible
          python311
          python311Packages.pillow
          python311Packages.boto3
          python311Packages.pytest
          checkov
          infracost
          nodejs_20
          nodePackages."@commitlint/cli"
          nodePackages."@commitlint/config-conventional"
          zip
          unzip
        ];
      };
    };
}
