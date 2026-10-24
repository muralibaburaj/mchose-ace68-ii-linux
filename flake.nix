{
  description = "MCHOSE Ace68-II advanced-key support for Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "mchose-adv-ace68-ii";
          version = "0.2.0";
          src = self;
          makeFlags = [
            "PREFIX=$(out)"
            "UDEVDIR=$(out)/lib/udev/rules.d"
          ];
          installTargets = [ "install" ];
          meta = {
            description = "MCHOSE Ace68-II advanced-key userspace bridge";
            homepage = "https://github.com/muralibaburaj/mchose-ace68-ii-linux";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.linux;
            mainProgram = "mchose-adv-ace68-ii";
          };
        };
      });

      # services.mchose-ace68-ii = { enable = true; bridge.enable = true; };
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.mchose-ace68-ii;
        in
        {
          options.services.mchose-ace68-ii = {
            enable = lib.mkEnableOption "udev access rules for the MCHOSE Ace68-II (WebHID / M HUB)";
            bridge.enable = lib.mkEnableOption "the mchose-adv userspace bridge (not with the HID-BPF fixup)";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "mchose-ace68-ii.packages.\${system}.default";
              description = "The mchose-adv package to use.";
            };
          };

          config = lib.mkIf cfg.enable {
            services.udev.packages = [ cfg.package ];
            boot.kernelModules = lib.mkIf cfg.bridge.enable [ "uinput" ];
            systemd.services.mchose-adv = lib.mkIf cfg.bridge.enable {
              description = "MCHOSE Ace68-II advanced-key bridge";
              wantedBy = [ "multi-user.target" ];
              after = [
                "systemd-udevd.service"
                "systemd-modules-load.service"
              ];
              serviceConfig = {
                ExecStart = "${lib.getExe cfg.package} --retry 2";
                Restart = "always";
                RestartSec = 2;
                Nice = -5;
              };
            };
          };
        };
    };
}
