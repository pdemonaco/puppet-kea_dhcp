# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Puppet module (`pdemon-kea_dhcp`) for installing and configuring ISC Kea DHCP server on RHEL/Rocky 8-9 systems. It uses PostgreSQL as the lease database backend.

## Build & Test Commands

```bash
# Install dependencies
pdk bundle install

# Run unit tests (rspec-puppet)
pdk test unit

# Run a single unit test file
pdk test unit --tests=spec/classes/kea_dhcp_spec.rb

# Run all linting
pdk exec rake lint

# Validate Puppet syntax
pdk validate

# Provision the acceptance test environment
pdk bundle exec rake 'litmus:provision_list[default]'
pdk bundle exec rake litmus:install_agent

# Run acceptance tests (requires Litmus provisioning)
pdk bundle exec rake litmus:install_module
pdk bundle exec rake litmus:acceptance:parallel

# Teardown the docker container
pdk bundle exec rake litmus:tear_down
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
