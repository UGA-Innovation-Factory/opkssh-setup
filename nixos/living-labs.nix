{ config, lib, pkgs, ... }:

let
  cfg = config.services.uga-living-labs;
  ugaIssuer = "https://login.microsoftonline.com/a8216c1e-4d63-4352-8c3b-50fa1f1475b1/v2.0";
  defaultIssuer =
    if cfg.opkssh.providers == [ ] then ugaIssuer else (lib.head cfg.opkssh.providers).issuer;

  factoryAccessMappings = lib.optional cfg.opkssh.enableFactoryAccess {
    user = cfg.factoryUser;
    role = cfg.factoryAccessGroup;
    issuer = defaultIssuer;
  };

  giteaAccessMappings = lib.optional cfg.giteaOpkssh.enable {
    user = cfg.giteaOpkssh.runUser;
    role = cfg.giteaOpkssh.accessRole;
    issuer = defaultIssuer;
  };

  effectiveRoleMappings = factoryAccessMappings ++ giteaAccessMappings ++ cfg.opkssh.roleMappings;

  factoryNoShellCommand = pkgs.writeShellScript "factory-ssh-no-shell" ''
    set -euo pipefail

    IDENTIFIED_USER="''${OPKSSH_IDENTIFIED_USER:-''${USER:-${cfg.factoryUser}}}"
    OIDC_SOURCE="''${OPKSSH_OIDC_SOURCE:-${cfg.oidcSourceName}}"

    cat <<EOF
Your authentication has passed as user ''${IDENTIFIED_USER} with OIDC source ''${OIDC_SOURCE}, but shell access is not enabled for this host.
If you are not the user that was identified, please run 'opkssh login'
EOF

    exit 1
  '';

  providerLine = provider:
    "${provider.issuer} ${provider.clientId} ${provider.ttl}";

  authGroupLine = entry:
    "${entry.user} oidc:groups:${entry.group} ${entry.issuer}";

  authRoleLine = entry:
    "${entry.user} oidc:roles:${entry.role} ${entry.issuer}";

  authEmailLine = entry:
    "${entry.user} ${entry.email} ${entry.issuer}";

  providersText = ''
    # Managed by services.uga-living-labs.
    ${lib.concatStringsSep "\n" (map providerLine cfg.opkssh.providers)}
  '';

  authIdText = ''
    # Managed by services.uga-living-labs.
    # principal identity issuer
    ${lib.concatStringsSep "\n" ((map authRoleLine effectiveRoleMappings) ++ (map authGroupLine cfg.opkssh.groupMappings) ++ (map authEmailLine cfg.opkssh.emailMappings))}
  '';

  hostRecordLines =
    map
      (host: "host-record=${host.name},${host.address}")
      cfg.internalNetwork.hosts;

  dhcpHostLines =
    map
      (lease: "dhcp-host=${lease.mac},${lease.address},${lease.hostname},${lease.leaseTime}")
      cfg.internalNetwork.dhcpStaticLeases;

  dhcpRangeLines =
    map
      (range: "dhcp-range=${range.start},${range.end},${range.leaseTime}")
      cfg.internalNetwork.dhcpRanges;

  dnsmasqSettings = lib.concatStringsSep "\n" ([
    "domain-needed"
    "bogus-priv"
    "expand-hosts"
    "domain=${cfg.internalNetwork.domain}"
    "local=/${cfg.internalNetwork.domain}/"
  ] ++ hostRecordLines ++ dhcpRangeLines ++ dhcpHostLines ++ lib.optional (cfg.internalNetwork.extraDnsmasqConfig != "") cfg.internalNetwork.extraDnsmasqConfig);

  hasAuthMappings = cfg.giteaOpkssh.enable || cfg.opkssh.roleMappings != [ ] || cfg.opkssh.groupMappings != [ ] || cfg.opkssh.emailMappings != [ ];

  jumpUsers = lib.concatStringsSep "," cfg.jumpHost.users;

  giteaOpksshBridge = pkgs.writeTextFile {
    name = "gitea-opkssh-authorized-keys";
    destination = "/bin/gitea-opkssh-authorized-keys";
    executable = true;
    text = builtins.readFile ../scripts/gitea_opkssh_authorized_keys;
  };

  giteaOpksshEnv = ''
    # Managed by services.uga-living-labs.
    GITEA_URL="${cfg.giteaOpkssh.url}"
    GITEA_TOKEN_FILE="${cfg.giteaOpkssh.tokenFile}"
    GITEA_BINARY="${cfg.giteaOpkssh.giteaBinary}"
    GITEA_CONFIG="${cfg.giteaOpkssh.configFile}"
    GITEA_WORK_PATH="${cfg.giteaOpkssh.workPath}"
    GITEA_RUN_USER="${cfg.giteaOpkssh.runUser}"
    GITEA_KEY_TITLE_PREFIX="${cfg.giteaOpkssh.keyTitlePrefix}"
    GITEA_REQUIRE_VERIFIED_EMAIL="${lib.boolToString cfg.giteaOpkssh.requireVerifiedEmail}"
    GITEA_SYNTHETIC_KEY_READ_ONLY="${lib.boolToString cfg.giteaOpkssh.syntheticKeyReadOnly}"
    OPKSSH_BINARY="${cfg.opkssh.package}/bin/opkssh"
  '';

  dnsDhcpFirewallForInterfaces =
    lib.genAttrs cfg.internalNetwork.interfaces (_: {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 67 ];
    });
in
{
  options.services.uga-living-labs = {
    enable = lib.mkEnableOption "UGA Manufacturing Living Labs remote development services";

    factoryUser = lib.mkOption {
      type = lib.types.str;
      default = "factory";
      description = "Default shared Linux principal used for bastion ProxyJump access.";
    };

    factoryAccessGroup = lib.mkOption {
      type = lib.types.str;
      default = "factory-ssh-access";
      description = "Entra app-role claim allowed to assume the shared factory user.";
    };

    oidcSourceName = lib.mkOption {
      type = lib.types.str;
      default = "UGA Entra";
      description = "Human-readable OIDC source name shown in the no-shell message.";
    };

    opkssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Configure OPKSSH provider and authorization files.";
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.opkssh or null;
        defaultText = lib.literalExpression "pkgs.opkssh or null";
        description = "OPKSSH package to install when available in nixpkgs.";
      };

      providers = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            alias = lib.mkOption {
              type = lib.types.str;
              default = "uga";
              description = "Human-readable provider alias.";
            };

            issuer = lib.mkOption {
              type = lib.types.str;
              default = ugaIssuer;
              description = "OIDC issuer accepted by OPKSSH.";
            };

            clientId = lib.mkOption {
              type = lib.types.str;
              default = "7f331a0a-da1a-4e13-8df0-e9baba02ed86";
              description = "OIDC client ID accepted by OPKSSH.";
            };

            ttl = lib.mkOption {
              type = lib.types.str;
              default = "12h";
              description = "Maximum OPKSSH token lifetime.";
            };
          };
        });
        default = [ { } ];
        description = "OPKSSH provider entries written to /etc/opk/providers.";
      };

      groupMappings = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            user = lib.mkOption {
              type = lib.types.str;
              description = "Local Linux principal.";
            };

            group = lib.mkOption {
              type = lib.types.str;
              description = "Entra group object ID or stable group claim value.";
            };

            issuer = lib.mkOption {
              type = lib.types.str;
              default = ugaIssuer;
              description = "OIDC issuer for this mapping.";
            };
          };
        });
        default = [ ];
        description = "Mappings from Entra groups to local Linux principals.";
      };

      roleMappings = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            user = lib.mkOption {
              type = lib.types.str;
              description = "Local Linux principal.";
            };

            role = lib.mkOption {
              type = lib.types.str;
              description = "OIDC role claim value, such as an Entra app role.";
            };

            issuer = lib.mkOption {
              type = lib.types.str;
              default = ugaIssuer;
              description = "OIDC issuer for this mapping.";
            };
          };
        });
        default = [ ];
        description = "Mappings from OIDC role claims to local Linux principals.";
      };

      emailMappings = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            user = lib.mkOption {
              type = lib.types.str;
              description = "Local Linux principal.";
            };

            email = lib.mkOption {
              type = lib.types.str;
              description = "OIDC email address or subject value.";
            };

            issuer = lib.mkOption {
              type = lib.types.str;
              default = ugaIssuer;
              description = "OIDC issuer for this mapping.";
            };
          };
        });
        default = [ ];
        description = "Mappings from individual OIDC identities to local Linux principals.";
      };

      enableFactoryAccess = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically map factoryAccessGroup to factoryUser as an oidc:roles entry in /etc/opk/auth_id.";
      };
    };

    jumpHost = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Configure sshd as an OPKSSH ProxyJump entry point.";
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "factory" ];
        description = "Linux principals allowed to perform SSH TCP forwarding.";
      };

      permitOpen = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "any" ];
        example = [ "cnc-controller-01.lab.livinglabs.internal:22" "robot-cell-02.lab.livinglabs.internal:22" ];
        description = "OpenSSH PermitOpen values for jump users.";
      };

      forceNoShell = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use a ForceCommand that prints a no-shell message for direct sessions while still allowing ProxyJump forwarding.";
      };

      createFactoryUser = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create the shared factory Unix account.";
      };

      clientAliveInterval = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 30;
        description = "Seconds between server keepalives for jump users.";
      };

      clientAliveCountMax = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 20;
        description = "Missed server keepalive responses before sshd disconnects jump users.";
      };
    };

    giteaOpkssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable dynamic OPKSSH-backed Git-over-SSH authentication for the Gitea SSH user.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:3000";
        description = "Local Gitea HTTP base URL used for API lookups.";
      };

      tokenFile = lib.mkOption {
        type = lib.types.str;
        default = "/etc/opk/gitea-token";
        description = "Path to a Gitea admin API token readable by the opksshuser group.";
      };

      giteaBinary = lib.mkOption {
        type = lib.types.str;
        default = "/usr/local/bin/gitea";
        description = "Path to the Gitea binary used for native static-key checks and serv commands.";
      };

      configFile = lib.mkOption {
        type = lib.types.str;
        default = "/etc/gitea/app.ini";
        description = "Path to Gitea app.ini.";
      };

      workPath = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional Gitea work path passed to the gitea command.";
      };

      runUser = lib.mkOption {
        type = lib.types.str;
        default = "git";
        description = "Unix SSH user used by Gitea.";
      };

      accessRole = lib.mkOption {
        type = lib.types.str;
        default = "factory-ssh-access";
        description = "OIDC role claim allowed to authenticate as the Gitea SSH user before Gitea email permissions are checked.";
      };

      keyTitlePrefix = lib.mkOption {
        type = lib.types.str;
        default = "opkssh-oidc";
        description = "Title prefix for synthetic Gitea key records created for OPKSSH identities.";
      };

      requireVerifiedEmail = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Only match verified Gitea email addresses to OPKSSH certificate identities.";
      };

      syntheticKeyReadOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create synthetic Gitea key records with read-only permissions.";
      };
    };

    internalNetwork = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Configure this host as the internal DNS/DHCP server.";
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = "livinglabs.internal";
        description = "Internal DNS domain served by dnsmasq.";
      };

      interfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "br-lab" "enp2s0" ];
        description = "Interfaces on which dnsmasq should listen.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open DNS and DHCP ports on the configured internal interfaces.";
      };

      hosts = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              example = "cnc-controller-01.livinglabs.internal";
              description = "Internal hostname.";
            };

            address = lib.mkOption {
              type = lib.types.str;
              example = "10.42.10.21";
              description = "Internal address.";
            };
          };
        });
        default = [ ];
        description = "Static internal DNS records.";
      };

      dhcpRanges = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            start = lib.mkOption {
              type = lib.types.str;
              example = "10.42.10.100";
              description = "Start of DHCP pool.";
            };

            end = lib.mkOption {
              type = lib.types.str;
              example = "10.42.10.199";
              description = "End of DHCP pool.";
            };

            leaseTime = lib.mkOption {
              type = lib.types.str;
              default = "12h";
              description = "DHCP lease duration.";
            };
          };
        });
        default = [ ];
        description = "DHCP ranges served by dnsmasq.";
      };

      dhcpStaticLeases = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            mac = lib.mkOption {
              type = lib.types.str;
              example = "02:00:00:00:10:21";
              description = "MAC address.";
            };

            address = lib.mkOption {
              type = lib.types.str;
              example = "10.42.10.21";
              description = "Static DHCP address.";
            };

            hostname = lib.mkOption {
              type = lib.types.str;
              example = "cnc-controller-01";
              description = "DHCP hostname.";
            };

            leaseTime = lib.mkOption {
              type = lib.types.str;
              default = "infinite";
              description = "DHCP lease duration.";
            };
          };
        });
        default = [ ];
        description = "Static DHCP leases.";
      };

      extraDnsmasqConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = ''
          dhcp-option=option:router,10.42.10.1
          dhcp-option=option:dns-server,10.42.10.1
        '';
        description = "Additional dnsmasq configuration for VLAN-specific DHCP options or local policy.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.jumpHost.enable || cfg.jumpHost.users != [ ];
          message = "services.uga-living-labs.jumpHost.users must not be empty when jumpHost.enable is true.";
        }
        {
          assertion = !cfg.jumpHost.enable || cfg.jumpHost.permitOpen != [ ];
          message = "services.uga-living-labs.jumpHost.permitOpen must not be empty when jumpHost.enable is true.";
        }
        {
          assertion = !cfg.internalNetwork.enable || cfg.internalNetwork.interfaces != [ ];
          message = "services.uga-living-labs.internalNetwork.interfaces must list at least one interface when internalNetwork.enable is true.";
        }
        {
          assertion = !cfg.giteaOpkssh.enable || cfg.opkssh.enable;
          message = "services.uga-living-labs.giteaOpkssh.enable requires opkssh.enable.";
        }
      ];
    }

    (lib.mkIf cfg.opkssh.enable {
      assertions = [
        {
          assertion = cfg.opkssh.package != null;
          message = "services.uga-living-labs.opkssh.package is null because pkgs.opkssh is unavailable in this nixpkgs. Set it to an OPKSSH package or overlay.";
        }
      ];

      environment.systemPackages = lib.optional (cfg.opkssh.package != null) cfg.opkssh.package
        ++ lib.optional cfg.giteaOpkssh.enable giteaOpksshBridge;

      users.groups.opksshuser = { };
      users.users.opksshuser = {
        isSystemUser = true;
        group = "opksshuser";
        home = "/var/empty";
        createHome = false;
        shell = pkgs.bashInteractive;
        description = "Low-privilege OPKSSH AuthorizedKeysCommand user";
      };

      users.users."${cfg.giteaOpkssh.runUser}".extraGroups =
        lib.mkIf cfg.giteaOpkssh.enable [ "opksshuser" ];

      services.openssh.enable = true;
      services.openssh.settings = lib.mkIf (cfg.opkssh.package != null) {
        AuthorizedKeysCommand =
          if cfg.giteaOpkssh.enable
          then "${giteaOpksshBridge}/bin/gitea-opkssh-authorized-keys --config /etc/opk/gitea-opkssh.env --principal %u --key-type %t --key %k"
          else "${cfg.opkssh.package}/bin/opkssh verify %u %k %t";
        AuthorizedKeysCommandUser =
          if cfg.giteaOpkssh.enable
          then cfg.giteaOpkssh.runUser
          else "opksshuser";
      };

      environment.etc."opk/providers" = {
        text = providersText;
        mode = "0640";
        user = "root";
        group = "opksshuser";
      };

      environment.etc."opk/gitea-opkssh.env" = lib.mkIf cfg.giteaOpkssh.enable {
        text = giteaOpksshEnv;
        mode = "0640";
        user = "root";
        group = "opksshuser";
      };
    })

    (lib.mkIf (cfg.opkssh.enable && (hasAuthMappings || cfg.opkssh.enableFactoryAccess)) {
      environment.etc."opk/auth_id" = {
        text = authIdText;
        mode = "0640";
        user = "root";
        group = "opksshuser";
      };
    })

    (lib.mkIf cfg.jumpHost.enable {
      services.openssh.enable = true;
      services.openssh.settings = {
        AllowTcpForwarding = lib.mkDefault "no";
        AllowAgentForwarding = lib.mkDefault "no";
        X11Forwarding = lib.mkDefault false;
      };

      users.users = lib.mkIf cfg.jumpHost.createFactoryUser {
        "${cfg.factoryUser}" = {
          isSystemUser = true;
          group = cfg.factoryUser;
          home = "/var/lib/${cfg.factoryUser}";
          createHome = true;
          shell = pkgs.bashInteractive;
          description = "Shared OPKSSH ProxyJump-only account";
        };
      };

      users.groups = lib.mkIf cfg.jumpHost.createFactoryUser {
        "${cfg.factoryUser}" = { };
      };

      services.openssh.extraConfig = ''
        Match User ${jumpUsers}
            AllowTcpForwarding yes
            PermitTTY no
            X11Forwarding no
            AllowAgentForwarding no
            ExposeAuthInfo yes
            SetEnv OPKSSH_IDENTIFIED_USER="${cfg.factoryUser}"
            ${lib.optionalString cfg.jumpHost.forceNoShell "ForceCommand ${factoryNoShellCommand}"}
            PermitOpen ${lib.concatStringsSep " " cfg.jumpHost.permitOpen}
            ClientAliveInterval ${toString cfg.jumpHost.clientAliveInterval}
            ClientAliveCountMax ${toString cfg.jumpHost.clientAliveCountMax}
      '';
    })

    (lib.mkIf cfg.internalNetwork.enable {
      services.dnsmasq.enable = true;
      services.dnsmasq.settings = {
        bind-interfaces = true;
        interface = cfg.internalNetwork.interfaces;
      };
      services.dnsmasq.extraConfig = dnsmasqSettings;

      networking.firewall.interfaces = lib.mkIf cfg.internalNetwork.openFirewall dnsDhcpFirewallForInterfaces;
    })
  ]);
}
