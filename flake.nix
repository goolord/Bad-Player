{
  description = "Discord bot that keeps a channel YouTube-links-only";

  # pinned by rev: no flake.lock, nothing local to generate one
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/7c8764b7c7b09b34f632464276218ef9090eaa11";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # oracle A1 is aarch64, E2 micro is x86_64
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./bad-player.cabal
          ./app
          ./src
          ./test
        ];
      };

      overrides = pkgs: hself: hsuper: {
        # marked broken only over stale bounds (data-default-class, typerep-map)
        calamity = lib.pipe hsuper.calamity [
          pkgs.haskell.lib.compose.doJailbreak
          pkgs.haskell.lib.compose.markUnbroken
        ];
        bad-player = hself.callCabal2nix "bad-player" src { };
      };

      # same GHC as cabal.project
      haskellPackagesFor = pkgs: pkgs.haskell.packages.ghc910.extend (overrides pkgs);

      badPlayerFor =
        pkgs:
        let
          # keeps GHC out of the runtime closure
          exe = pkgs.haskell.lib.compose.justStaticExecutables (haskellPackagesFor pkgs).bad-player;
        in
        exe.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
          # don't rely on the host having a CA bundle where tls looks for one
          postFixup = (old.postFixup or "") + ''
            wrapProgram $out/bin/bad-player \
              --set-default SYSTEM_CERTIFICATE_PATH ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';
          meta = (old.meta or { }) // {
            mainProgram = "bad-player";
          };
        });
    in
    {
      packages = forAllSystems (pkgs: rec {
        bad-player = badPlayerFor pkgs;
        default = bad-player;
      });

      # building runs the tests
      checks = forAllSystems (pkgs: {
        bad-player = badPlayerFor pkgs;
      });

      devShells = forAllSystems (
        pkgs:
        let
          hp = haskellPackagesFor pkgs;
        in
        {
          default = hp.shellFor {
            packages = p: [ p.bad-player ];
            nativeBuildInputs = [ pkgs.cabal-install ];
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.bad-player;
        in
        {
          options.services.bad-player = {
            enable = lib.mkEnableOption "the Bad Player Discord bot";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "bad-player.packages.\${system}.default";
              description = "Bad Player package to run.";
            };

            tokenFile = lib.mkOption {
              # str, not path: a path would copy the secret into the store
              type = lib.types.str;
              example = "/etc/bad-player/token";
              description = "File with the bot token. Loaded as a systemd credential, so it can be root-only.";
            };

            playlistChannel = lib.mkOption {
              type = lib.types.str;
              default = "bad-playlist";
              description = "Name of the YouTube-links-only channel.";
            };

            catchUpHours = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 24;
              description = "How far back to recheck the channel on connect, to cover downtime. 0 disables.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.bad-player = {
              description = "Bad Player Discord bot";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              # outages can outlast the default burst limit
              startLimitIntervalSec = 0;

              environment = {
                BOT_TOKEN_FILE = "%d/bot-token";
                PLAYLIST_CHANNEL = cfg.playlistChannel;
                CATCHUP_HOURS = toString cfg.catchUpHours;
              };

              serviceConfig = {
                ExecStart = lib.getExe cfg.package;
                LoadCredential = "bot-token:${cfg.tokenFile}";
                Restart = "always";
                RestartSec = "10s";

                # uses tens of MB; this is a safety net for 1G VMs
                MemoryMax = "512M";

                DynamicUser = true;
                CapabilityBoundingSet = "";
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectProc = "invisible";
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                  "AF_NETLINK"
                ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                LockPersonality = true;
                SystemCallArchitectures = "native";
                SystemCallFilter = [ "@system-service" ];
              };
            };
          };
        };
    };
}
