# RULES
- CONSTRAINTS: Keep changes minimal; don’t refactor unrelated code; no new deps.
- OUTPUT: (1) files changed list (2) patch (3) short rationale.
- DON’T: explain basics, restate prompt, or list possibilities.
- Before editing code: give a plan in <=5 bullets, each <=12 words. Then implement. No extra commentary.

# Workflow
- Always perform lint checks when you are done making a series of changes
- Prefer single tests, not the entire suite, for performance
- Do not evaluate acceptance tests unless asked

# Code style
- Use conventional commit syntax for commit messages

## Build & Test Commands


### Validate Puppet syntax

```bash
pdk validate
```

### Unit Tests

```bash
# Run all unit tests
pdk test unit

# Run a single unit test file
pdk test unit --tests=spec/classes/kea_dhcp_spec.rb
```

### Acceptance Tests

```bash
# Run all acceptance tests
pdk bundle exec rake litmus:acceptance:parallel

# Run a single acceptance test
pdk-litmus-test spec/acceptance/kea_dhcp_spec.json
```

## Architecture

### Module Structure

The module follows the standard Puppet pattern with `install` -> `config` -> `service` class ordering:

- `kea_dhcp` (main class) - Entry point, includes the three subclasses with ordering constraints. Accepts parameters for both DHCPv4 and DDNS server configuration.
- `kea_dhcp::install` - Installs the `isc-kea` package and backend dependencies
- `kea_dhcp::config` - Manages the DHCPv4 and DDNS server configurations via custom types. Declares `kea_dhcp_v4_server` and conditionally declares `kea_ddns_server` based on `enable_ddns` parameter.
- `kea_dhcp::service` - Manages kea-dhcp4, kea-dhcp6, and kea-dhcp-ddns services

### Custom Resource Types

The module provides custom types in `lib/puppet/type/`:

#### DHCPv4 Types
- `kea_dhcp_v4_server` - Manages server-level DHCPv4 configuration (lease database, global options, DDNS connectivity). Only one instance named `dhcp4` is allowed. Managed centrally via `kea_dhcp::config`.
- `kea_dhcp_v4_scope` - Manages individual DHCPv4 subnets (pools, per-subnet options). Multiple instances allowed.
- `kea_dhcp_v4_reservation` - Manages static IP reservations within subnets.

These types use the JSON provider which reads and writes `/etc/kea/kea-dhcp4.conf`.

#### DDNS Types
- `kea_ddns_server` - Manages server-level DDNS configuration (IP, port, TSIG keys). Only one instance named `dhcp-ddns` is allowed. Managed centrally via `kea_dhcp::config` when `enable_ddns` is true.
- `kea_ddns_domain` - Manages DDNS domain configurations for forward and reverse zones.

These types use the JSON provider which reads and writes `/etc/kea/kea-dhcp-ddns.conf`.

### Shared Provider Logic

#### DHCPv4 Provider Base
`lib/puppet_x/kea_dhcp/provider/dhcp4_json.rb` contains the base provider class for DHCPv4 resources:
- JSON config file caching and dirty tracking for `/etc/kea/kea-dhcp4.conf`
- Staged writes to temp files with `kea-dhcp4 -t` validation before committing
- Commit coordination between server and scope providers
- Sensitive value unwrapping for database passwords
- Server provider registers as commit controller, scope provider commits uncontrolled changes

#### DDNS Provider Base
`lib/puppet_x/kea_dhcp/provider/ddns_json.rb` contains the base provider class for DDNS resources:
- JSON config file caching and dirty tracking for `/etc/kea/kea-dhcp-ddns.conf`
- Staged writes to temp files with `kea-dhcp-ddns -t` validation before committing
- Commit coordination between server and domain providers
- Server provider registers as commit controller, domain provider commits uncontrolled changes
- Follows same pattern as DHCPv4 providers but manages separate config file

### Backend Support

Currently only PostgreSQL is supported (`Kea_Dhcp::Backends` type). The `kea_dhcp::install::postgresql` class:
- Creates a dedicated PostgreSQL instance using `puppetlabs/postgresql`
- Creates the database and user
- Runs `kea-admin db-init` to initialize the schema

### Platform Support

RedHat-family only (RHEL 8-9, Rocky 8-9). Uses ISC's yum repository for package installation via `kea_dhcp::install::yum_isc_repos`.
