# Remote Development Architecture

## Goals

The Living Labs SSH entry point should provide:

- OIDC-backed SSH authentication through OPKSSH.
- A public entry point at `factory.uga.edu`.
- `ssh -J` access to internal hosts whose names only need to resolve from the
  factory network.
- Independent login policy on each internal host.
- Room for subnet and VLAN isolation when lab equipment or projects require it.

## Recommended Shape

```text
Internet
  |
  | ssh with OPKSSH certificate
  v
factory.uga.edu
  - public DNS
  - OpenSSH server with OPKSSH AuthorizedKeysCommand
  - shared factory principal allowed to TCP-forward to approved lab targets
  - resolver/search domains for lab-only hostnames
  - firewall rules per lab subnet or VLAN
  |
  | direct-tcpip forwarding from ssh -J
  v
internal lab hosts
  - private DNS or split-horizon DNS
  - OPKSSH server policy
  - local Linux users such as dev, robotics, operator
```

## Authentication Layers

OPKSSH verifies a signed OIDC identity embedded in the SSH certificate. The
server trust boundary is `/etc/opk/providers`, which lists acceptable issuers,
client IDs, and token lifetime policy.

Authorization is separate. `/etc/opk/auth_id` maps a Linux principal to one of:

- an OIDC email address,
- an OIDC subject ID,
- an OIDC group claim such as `oidc:groups:<group-id>`.
- an OIDC role claim such as `oidc:roles:<role-name>`.

For UGA shared users, prefer Entra group mappings. For private hosts or smaller
collaborations, use explicit email or subject mappings.

## Jump Host Policy

OpenSSH `ProxyJump` works by asking the bastion to open a TCP connection to the
target host and port. That means target hostnames can resolve using the bastion's
DNS context, which is exactly what we want for private lab DNS.

Keep jump access narrow:

- use the shared `factory` Linux principal for bastion entry,
- map the Entra `factory-ssh-access` app role to that principal as
  `oidc:roles:factory-ssh-access`,
- set `AllowTcpForwarding yes` only for those principals,
- disable TTY, X11, and agent forwarding for jump principals,
- use `ForceCommand` so direct sessions receive a no-shell message,
- keep `ClientAliveInterval` and `ClientAliveCountMax` inside the same
  `Match User factory` block as the forwarding policy,
- use `PermitOpen host:22` allowlists for sensitive VLANs,
- use firewall rules so the bastion can only reach the internal hosts it should.

The `server_setup --configure-jump-host` path installs a conservative starting
point in `/etc/ssh/sshd_config.d/60-uga-living-labs-jump.conf`.

## VLAN and Subnet Isolation

Use network controls as the source of truth for isolation. OPKSSH should decide
who can log in as a Linux user; it should not be the only boundary preventing
access to a machine.

Suggested pattern:

| Segment | Bastion route | SSH forwarding | Internal OPKSSH policy |
| --- | --- | --- | --- |
| shared-dev | allowed | `factory` via broad `PermitOpen` or subnet allowlist | Entra group to `dev` |
| robotics | allowed only from bastion | explicit host allowlist | robotics group to `robotics` |
| vendor/private | time-bound or ticketed | explicit host allowlist | email/sub map |
| controls/safety | default denied | exceptional, audited | named operators only |

## NixOS DNS/DHCP Server

The NixOS module in `nixos/living-labs.nix` is meant to support a combined
internal network services host:

- `services.dnsmasq` serves internal hostnames such as
  `cnc-controller-01.livinglabs.internal`.
- DHCP ranges and static leases are declared in Nix, so lab inventory changes can
  move through code review.
- Firewall rules for DNS and DHCP are opened on the declared internal interfaces
  by default.
- The same host can also be the OPKSSH bastion by enabling
  `services.uga-living-labs.jumpHost`.
- `jumpHost.permitOpen` should mirror the DNS/DHCP inventory for sensitive
  subnets rather than defaulting to broad forwarding.

This keeps private hostnames private: clients ask `factory.uga.edu` to open the
connection, and `factory.uga.edu` resolves the internal target using its own DNS
view.

## Gitea Coexistence

If `factory.uga.edu` is already a Gitea SSH endpoint, avoid overloading Gitea's
Git SSH account as the general jump account. Prefer one of these shapes:

- run system sshd on a separate port or hostname for OPKSSH jump access,
- use a dedicated bastion VM behind the same public DNS name,
- keep Gitea's Git command restrictions separate from human shell or jump access.

This avoids accidentally giving a Git-only SSH identity TCP-forwarding privileges.
