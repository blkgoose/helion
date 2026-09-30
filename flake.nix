{
  description = "helion - ION tactical client (Godot 4)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        godot = pkgs.godot_4;
        templates = pkgs.godot_4-export-templates-bin;
      in
      {
        apps.default = {
          type = "app";
          program = toString (pkgs.writeShellScript "helion-editor" ''
            exec ${godot}/bin/godot4 --editor --path . "$@"
          '');
        };

        devShells.default = pkgs.mkShell {
          packages = [
            godot
            pkgs.vulkan-tools
            pkgs.git
          ];

          GODOT_EXPORT_TEMPLATES = "${templates}";

          shellHook = ''
            tpl_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates"
            tpl_ver="$(cat ${templates}/share/godot/export_templates/*/version.txt)"
            mkdir -p "$tpl_dir"
            ln -sfn "$(echo ${templates}/share/godot/export_templates/*)" "$tpl_dir/$tpl_ver"
          '';
        };
      });
}
