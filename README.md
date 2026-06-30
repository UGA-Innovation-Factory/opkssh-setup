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
  entries for `ProxyJump` (Linux/macOS bash script).
- `client_setup.ps1` PowerShell version for Windows environments.
- `client_setup.bat` Windows batch file launcher for the PowerShell script.
- `server_setup` installs/configures OPKSSH on Linux servers, registers the UGA
  Entra issuer, optionally enables jump-host forwarding policy, and can apply
  authorization maps.
- `flake.nix` packages the scripts and exports a NixOS module.
- `nixos/living-labs.nix` declaratively configures OPKSSH policy, jump-host
  forwarding, and optional internal DNS/DHCP service.
- `scripts/living_labs_auth_sync` compiles Entra group and email maps into
  `/etc/opk/auth_id`.
- `scripts/gitea_opkssh_authorized_keys` bridges OPKSSH certificates into
  Gitea Git-over-SSH authorization without hard-coded Gitea users.
- `examples/entra_groups.tsv` maps Linux users to Entra group IDs or emitted
  group names.
- `examples/email_users.tsv` maps Linux users to individual OIDC emails or
  subject IDs.
- `docs/architecture.md` describes the deployment model and isolation points.

## Client Setup

### Linux and macOS

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

### Windows

Using PowerShell:

```powershell
.\client_setup.ps1
opkssh login uga
ssh factory
ssh -J factory dev@cnc-controller-01.lab
```

The script will automatically attempt to install opkssh using winget if it's not found on your PATH.

Or using Command Prompt:

```cmd
client_setup.bat
opkssh login uga
ssh factory
ssh -J factory dev@cnc-controller-01.lab
```

To customize the configuration on Windows:

```powershell
.\client_setup.ps1 `
  -FactoryHost factory.uga.edu `
  -FactoryAlias factory `
  -InternalPattern "*.livinglabs.internal" `
  -FactoryUser factory `
  -RemoteUser dev
```

Or use `-LinuxUser` to set both factory and internal usernames:

```powershell
.\client_setup.ps1 -LinuxUser jdoe
```

For help with all options:

```powershell
Get-Help .\client_setup.ps1 -Detailed
```

### Notes for All Platforms

The generated SSH config uses OPKSSH's default generated key,
`~/.ssh/id_ecdsa`, with `IdentitiesOnly yes`.

The OPKSSH settings are applied only to the local SSH alias, such as `factory`,
not to the raw hostname `factory.uga.edu`. This keeps normal Gitea usage like
`ssh git@factory.uga.edu` or Git remotes using `git@factory.uga.edu:...`
from inheriting the bastion-only identity and password settings.

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

The generated jump-host sshd policy also sets:

```sshconfig
ClientAliveInterval 30
ClientAliveCountMax 20
```

The generated client config sets:

```sshconfig
PreferredAuthentications publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
BatchMode yes
ServerAliveInterval 20
ServerAliveCountMax 6
```

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

## Gitea Git SSH With OPKSSH

On a Gitea host, the system sshd can use the Gitea-aware OPKSSH bridge instead
of calling `opkssh verify` directly:

```sh
sudo install -m 640 -o root -g opksshuser /dev/null /etc/opk/gitea-token
sudo editor /etc/opk/gitea-token
sudo ./server_setup --configure-jump-host --configure-gitea-opkssh
```

`/etc/opk/gitea-token` must contain a Gitea admin API token. The bridge uses it
only for local API lookups and synthetic key record creation.

The bridge keeps native Gitea keys working. For `git@factory.uga.edu`, sshd
first asks Gitea's native `gitea keys` command whether the offered key is a
normal static Gitea key. If that fails and the offered key is an OPKSSH user
certificate, the bridge:

- verifies the certificate with OPKSSH against the `git` Unix principal,
- reads the OPKSSH certificate Key ID as the OIDC email address,
- searches Gitea for exactly one matching email address, verified by default,
- creates or reuses an inert synthetic Gitea SSH key record for that user,
- emits a forced `gitea serv key-<id>` authorized-keys line for the presented
  OPKSSH certificate.

No Gitea usernames are hard-coded. The effective Git permission check remains
inside Gitea because `gitea serv key-<id>` runs as the matched Gitea user and
enforces normal repository permissions.

When `--configure-gitea-opkssh` is enabled, `AuthorizedKeysCommandUser` is set
to the configured Gitea SSH Unix user, `git` by default, because that is the
documented execution model for `gitea keys`. The setup script adds that user to
the `opksshuser` group so the same bridge can also read `/etc/opk/providers`,
`/etc/opk/auth_id`, and `/etc/opk/gitea-token`.

The OPKSSH gate for the `git` Unix principal defaults to the same Entra app
role used by the factory jump user:

```text
git oidc:roles:factory-ssh-access https://login.microsoftonline.com/a8216c1e-4d63-4352-8c3b-50fa1f1475b1/v2.0
```

Use `--gitea-access-role ROLE` if Git SSH should require a different Entra app
role before Gitea email and repository permissions are checked.

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
- optionally enable `services.uga-living-labs.giteaOpkssh` so Git-over-SSH can
  authenticate OPKSSH certificates through live Gitea email lookups.

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
