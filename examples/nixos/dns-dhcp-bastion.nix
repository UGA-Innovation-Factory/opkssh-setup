{ ... }:

{
  imports = [
    # In a flake-based host, prefer:
    # inputs.opkssh-setup.nixosModules.living-labs
    ../../nixos/living-labs.nix
  ];

  services.uga-living-labs = {
    enable = true;
    factoryUser = "factory";
    factoryAccessGroup = "factory-ssh-access";

    opkssh = {
      enable = true;

      groupMappings = [
        {
          user = "dev";
          group = "00000000-0000-0000-0000-000000000000";
        }
        {
          user = "robotics";
          group = "11111111-1111-1111-1111-111111111111";
        }
      ];

      emailMappings = [
        {
          user = "dev";
          email = "alice@example.edu";
        }
      ];
    };

    jumpHost = {
      enable = true;
      users = [ "factory" ];
      permitOpen = [
        "cnc-controller-01.livinglabs.internal:22"
        "robot-cell-02.livinglabs.internal:22"
      ];
    };

    internalNetwork = {
      enable = true;
      domain = "livinglabs.internal";
      interfaces = [ "br-lab" ];

      hosts = [
        {
          name = "cnc-controller-01.livinglabs.internal";
          address = "10.42.10.21";
        }
        {
          name = "robot-cell-02.livinglabs.internal";
          address = "10.42.20.22";
        }
      ];

      dhcpRanges = [
        {
          start = "10.42.10.100";
          end = "10.42.10.199";
          leaseTime = "12h";
        }
      ];

      dhcpStaticLeases = [
        {
          mac = "02:00:00:00:10:21";
          address = "10.42.10.21";
          hostname = "cnc-controller-01";
        }
        {
          mac = "02:00:00:00:20:22";
          address = "10.42.20.22";
          hostname = "robot-cell-02";
        }
      ];

      extraDnsmasqConfig = ''
        dhcp-option=option:router,10.42.10.1
        dhcp-option=option:dns-server,10.42.10.1
      '';
    };
  };
}
