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

- `kea_dhcp` (main class) - Entry point, includes the three subclasses with ordering constraints
- `kea_dhcp::install` - Installs the `isc-kea` package and backend dependencies
- `kea_dhcp::config` - Manages the DHCPv4 server configuration via custom types
- `kea_dhcp::service` - Manages kea-dhcp4, kea-dhcp6, and kea-dhcp-ddns services

### Custom Resource Types

The module provides two custom types in `lib/puppet/type/`:

- `kea_dhcp_v4_server` - Manages server-level DHCPv4 configuration (lease database, global options). Only one instance named `dhcp4` is allowed.
- `kea_dhcp_v4_scope` - Manages individual DHCPv4 subnets (pools, per-subnet options)

Both types use the JSON provider in `lib/puppet/provider/*/json.rb` which reads and writes `/etc/kea/kea-dhcp4.conf`.

### Shared Provider Logic

`lib/puppet_x/kea_dhcp/provider/json.rb` contains the base provider class with:
- JSON config file caching and dirty tracking
- Staged writes to temp files with `kea-dhcp4 -t` validation before committing
- Commit coordination between server and scope providers
- Sensitive value unwrapping for database passwords

### Backend Support

Currently only PostgreSQL is supported (`Kea_Dhcp::Backends` type). The `kea_dhcp::install::postgresql` class:
- Creates a dedicated PostgreSQL instance using `puppetlabs/postgresql`
- Creates the database and user
- Runs `kea-admin db-init` to initialize the schema

### Platform Support

RedHat-family only (RHEL 8-9, Rocky 8-9). Uses ISC's yum repository for package installation via `kea_dhcp::install::yum_isc_repos`.
