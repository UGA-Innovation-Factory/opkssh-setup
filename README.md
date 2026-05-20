# UGA Manufacturing Living Labs OPKSSH Setup

This repository bootstraps OPKSSH-based SSH access for the UGA Manufacturing
Living Labs remote-development entry point.

The intended pattern is:

```text
developer laptop
  -> ssh/opkssh login to factory.uga.edu
  -> OpenSSH ProxyJump forwarding
  -> internal lab hosts resolved from the factory.uga.edu network context
```

`factory.uga.edu` is the public SSH bastion. Internal lab machines can remain on
private DNS, private addresses, and isolated VLANs or subnets as long as the
bastion can resolve and route to the subset they should expose.

## Files

- `client_setup` writes the UGA OPKSSH client config and optional `~/.ssh/config`
  entries for `ProxyJump`.
- `server_setup` installs/configures OPKSSH on Linux servers, registers the UGA
  Entra issuer, optionally enables jump-host forwarding policy, and can apply
  authorization maps.
- `flake.nix` packages the scripts and exports a NixOS module.
- `nixos/living-labs.nix` declaratively configures OPKSSH policy, jump-host
  forwarding, and optional internal DNS/DHCP service.
- `scripts/living_labs_auth_sync` compiles Entra group and email maps into
  `/etc/opk/auth_id`.
- `examples/entra_groups.tsv` maps Linux users to Entra group IDs or emitted
  group names.
- `examples/email_users.tsv` maps Linux users to individual OIDC emails or
  subject IDs.
- `docs/architecture.md` describes the deployment model and isolation points.

## Client Setup

```sh
./client_setup
opkssh login uga
ssh factory
ssh -J factory dev@cnc-controller-01.lab
```

To install a different internal host pattern in `~/.ssh/config`:

```sh
./client_setup \
  --factory-host factory.uga.edu \
  --factory-alias factory \
  --internal-pattern "*.livinglabs.internal" \
  --factory-user factory \
  --remote-user dev
```

The generated SSH config uses OPKSSH's default generated key,
`~/.ssh/id_ecdsa`, with `IdentitiesOnly yes`.

## Bastion Setup

On `factory.uga.edu` or a dedicated SSH bastion host:

```sh
sudo ./server_setup --configure-jump-host --group-map examples/entra_groups.tsv
```

This configures the UGA Entra OPKSSH provider and writes an sshd snippet allowing
the shared `factory` Linux principal to perform TCP forwarding for `ssh -J`.
It also ensures this OPKSSH authorization exists, matching the Entra app-role
claim emitted as `roles: ["factory-ssh-access"]`:

```text
factory oidc:roles:factory-ssh-access https://login.microsoftonline.com/a8216c1e-4d63-4352-8c3b-50fa1f1475b1/v2.0
```

Direct shell sessions as `factory` are denied with a message:

```text
Your authentication has passed as user factory with OIDC source UGA Entra, but shell access is not enabled for this host.
If you are not the user that was identified, please run 'opkssh login'
```

`ssh -J factory ...` still works because it uses SSH TCP forwarding rather than
an interactive shell.

To allow additional forwarding-only principals:

```sh
sudo ./server_setup \
  --configure-jump-host \
  --jump-principals "factory,dev,robotics" \
  --group-map examples/entra_groups.tsv
```

For tighter network policy, replace the default `PermitOpen any` with a
space-separated allowlist:

```sh
sudo ./server_setup \
  --configure-jump-host \
  --permit-open "cnc-controller-01.lab:22 robot-cell-02.lab:22" \
  --group-map examples/entra_groups.tsv
```

## Internal Host Setup

Install OPKSSH on each internal host that should independently verify user
identity:

```sh
sudo ./server_setup --group-map examples/entra_groups.tsv
```

For private lab machines that are not driven by Entra groups:

```sh
sudo ./server_setup --email-map examples/email_users.tsv
```

The bastion controls reachability. The internal host controls login
authorization. Use both layers: route/firewall/VLAN policy for network
segmentation, and OPKSSH `auth_id` policy for who can assume each Linux user.

## Nix Flake and NixOS

This repository can be used as a flake:

```sh
nix run github:UGA-Living-Labs/opkssh-setup
nix build github:UGA-Living-Labs/opkssh-setup
```

For a NixOS host, import the module and configure the pieces you need:

```nix
{
  inputs.opkssh-setup.url = "github:UGA-Living-Labs/opkssh-setup";

  outputs = { self, nixpkgs, opkssh-setup, ... }: {
    nixosConfigurations.factory = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        opkssh-setup.nixosModules.living-labs
        ./configuration.nix
      ];
    };
  };
}
```

The module lives at `services.uga-living-labs`. It can:

- install the OPKSSH package when available in nixpkgs,
- write `/etc/opk/providers`,
- write `/etc/opk/auth_id` from Entra group and email mappings, including the
  default `factory -> oidc:roles:factory-ssh-access` mapping,
- configure OpenSSH as a `ProxyJump` entry point,
- configure `dnsmasq` for internal DNS and DHCP on the lab network,
- open DNS/DHCP firewall ports on the configured internal interfaces.

See `examples/nixos/dns-dhcp-bastion.nix` for a combined DNS/DHCP and bastion
host serving `livinglabs.internal`.

## Notes

- Prefer Entra group object IDs in `examples/entra_groups.tsv` unless the token
  reliably emits stable group names.
- Do not reuse an OIDC client ID that is used by another application audience.
- Keep Gitea's Git-over-SSH behavior separate from the OPKSSH bastion role when
  possible. A dedicated system sshd endpoint is easier to reason about than
  mixing Git command authorization and development jump access on the same Unix
  account.
