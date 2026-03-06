# kea_dhcp

#### Table of Contents

1. [Description](#description)
2. [Setup](#setup)
    * [What kea_dhcp affects](#what-kea_dhcp-affects)
        * [Packages](#1---packages)
        * [PostgreSQL Backend](#2---postgresql-backend)
        * [Configuration](#3---configuration)
    * [Setup Requirements](#setup-requirements)
    * [Beginning with kea_dhcp](#beginning-with-kea_dhcp)
3. [Usage](#usage)
    * [Server with Global Options](#server-with-global-options)
    * [Database Backend Installation Modes](#database-backend-installation-modes)
        * [Dedicated PostgreSQL instance (default)](#dedicated-postgresql-instance-default)
        * [Existing default PostgreSQL instance](#existing-default-postgresql-instance)
        * [Externally managed database](#externally-managed-database)
    * [Defining Subnets](#defining-subnets)
    * [Host Reservations](#host-reservations)
    * [Host Reservation Backend](#host-reservation-backend)
        * [Inline storage (default)](#inline-storage-default)
        * [PostgreSQL host database](#postgresql-host-database)
        * [Transitioning from inline to host database](#transitioning-from-inline-to-host-database)
    * [Interface Configuration](#interface-configuration)
        * [Listen on all interfaces (default)](#listen-on-all-interfaces-default)
        * [Listen on specific interfaces](#listen-on-specific-interfaces)
        * [Bind to a specific IP address on an interface](#bind-to-a-specific-ip-address-on-an-interface)
        * [Set the socket type](#set-the-socket-type)
    * [Dynamic DNS (DDNS)](#dynamic-dns-ddns)
        * [Basic DDNS Configuration](#basic-ddns-configuration)
        * [DDNS with TSIG Authentication](#ddns-with-tsig-authentication)
        * [DDNS Domain Configuration](#ddns-domain-configuration)
        * [DDNS Behavioral Parameters](#ddns-behavioral-parameters)
    * [Hiera Example](#hiera-example)
        * [Inline reservations (default)](#inline-reservations-default)
        * [PostgreSQL host database](#postgresql-host-database-1)
        * [DDNS with file-backed TSIG keys](#ddns-with-file-backed-tsig-keys)
4. [Reference](#reference)
5. [Limitations](#limitations)
6. [Development](#development)

## Description

The kea_dhcp module installs, configures, and manages the [ISC Kea DHCP](https://www.isc.org/kea/) server. It provisions a PostgreSQL backend for lease storage and provides custom types for managing DHCPv4 server configuration, subnet scopes, host reservations, and Dynamic DNS (DDNS) integration.

## Setup

### What kea_dhcp affects

This module impacts three main areas:

#### 1 - Packages

The `isc-kea` package is installed from the official ISC Cloudsmith repository. Repository management is handled automatically for RedHat-family systems.

#### 2 - PostgreSQL Backend

How the PostgreSQL backend is provisioned depends on the `lease_backend_install_mode` parameter:

| Mode | Behaviour |
|---|---|
| `instance` (default) | Creates a dedicated PostgreSQL instance on port 5433 with its own data directory |
| `database` | Adds the Kea database to the existing default PostgreSQL instance |
| `none` | Skips all database provisioning; the database is managed externally |

In all cases the Kea schema is initialised via `kea-admin db-init` when the database is first created.

#### 3 - Configuration

The module manages `/etc/kea/kea-dhcp4.conf` and `/etc/kea/kea-dhcp-ddns.conf` through custom resource types. Configuration changes are validated with `kea-dhcp4 -t` and `kea-dhcp-ddns -t` respectively before being committed.

### Setup Requirements

* RedHat-family OS (RHEL 8-9, Rocky 8-9)
* The `puppetlabs/postgresql` module for database provisioning

### Beginning with kea_dhcp

A minimal declaration requires only the database password:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
}
```

## Usage

### Server with Global Options

Configure the DHCPv4 server with default options applied to all subnets:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  array_dhcp4_server_options  => [
    { 'name' => 'routers', 'data' => '192.0.2.1' },
  ],
  enable_ddns                 => false,
  enable_ctrl_agent           => false,
}
```

### Database Backend Installation Modes

#### Dedicated PostgreSQL instance (default)

Creates a new PostgreSQL instance exclusively for Kea, running on port 5433 under its own system user. This is the recommended mode for production deployments where isolation is desired.

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  array_dhcp4_server_options  => [
    { 'name' => 'routers', 'data' => '192.0.2.1' },
  ],
  enable_ddns                 => false,
  enable_ctrl_agent           => false,
  lease_backend_install_mode  => 'instance',
}
```

#### Existing default PostgreSQL instance

Adds the Kea database to the default PostgreSQL instance already running on the node. Use `lease_database_port` to match the port of the existing instance (typically 5432).

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  array_dhcp4_server_options  => [
    { 'name' => 'routers', 'data' => '192.0.2.1' },
  ],
  enable_ddns                 => false,
  enable_ctrl_agent           => false,
  lease_database_port         => 5432,
  lease_backend_install_mode  => 'database',
}
```

#### Externally managed database

Skips all database provisioning. Use this when the PostgreSQL database is managed on a separate host or by another Puppet module. Set `lease_database_host` to the remote server address.

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  array_dhcp4_server_options  => [
    { 'name' => 'routers', 'data' => '192.0.2.1' },
  ],
  enable_ddns                 => false,
  enable_ctrl_agent           => false,
  lease_database_host         => 'database1.example.org',
  lease_backend_install_mode  => 'none',
}
```

### Defining Subnets

Use `kea_dhcp_v4_scope` resources to define DHCPv4 subnets:

```puppet
kea_dhcp_v4_scope { 'subnet-a':
  subnet  => '192.0.2.0/24',
  pools   => ['192.0.2.10 - 192.0.2.200'],
  options => [
    { name => 'routers', data => '192.0.2.1' },
  ],
}

kea_dhcp_v4_scope { 'subnet-b':
  subnet  => '198.51.100.0/24',
  pools   => ['198.51.100.10 - 198.51.100.200'],
  options => [
    { name => 'routers', data => '198.51.100.1' },
  ],
}
```

Multiple scopes are aggregated into a single configuration file. The provider preserves unmanaged keys in the configuration, allowing manual additions to coexist with Puppet-managed resources.

### Host Reservations

Reserve specific IP addresses for known hosts using `kea_dhcp_v4_reservation`. The subnet is automatically detected from the IP address.

The `hostname` parameter is a namevar, which means the resource title becomes the hostname unless you explicitly specify a different hostname. This makes common cases more concise:

```puppet
# Resource title becomes the hostname (recommended)
kea_dhcp_v4_reservation { 'fileserver':
  ensure          => present,
  identifier_type => 'hw-address',
  identifier      => '00:11:22:33:44:55',
  ip_address      => '192.0.2.10',
}

# Use explicit hostname to override the title
kea_dhcp_v4_reservation { 'printer-definitions':
  ensure          => present,
  identifier_type => 'client-id',
  identifier      => '01:aa:bb:cc:dd:ee:ff',
  ip_address      => '192.0.2.20',
  hostname        => 'printer-1',
}

# Without hostname parameter, title is used
kea_dhcp_v4_reservation { 'laptop':
  ensure          => present,
  identifier_type => 'hw-address',
  identifier      => 'a1:b2:c3:d4:e5:f6',
  ip_address      => '192.0.2.30',
}
```

The provider automatically finds the correct subnet by matching the IP address against configured subnet ranges. You can also explicitly specify the subnet using `scope_id` if needed.

Uniqueness is enforced within each subnet - duplicate identifiers, IP addresses, or hostnames will be rejected.

### Host Reservation Backend

By default, reservations are stored inline in `kea-dhcp4.conf` (the `json` provider). For larger environments, reservations can be stored in a separate PostgreSQL database using the `hosts-database` backend. This enables the `unix_socket` provider, which manages reservations through the `kea-dhcp4` control socket at runtime.

#### Inline storage (default)

No additional configuration is required. Reservations are written directly to `kea-dhcp4.conf`:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
}

kea_dhcp_v4_reservation { 'fileserver':
  ensure          => present,
  identifier_type => 'hw-address',
  identifier      => '00:11:22:33:44:55',
  ip_address      => '192.0.2.10',
}
```

#### PostgreSQL host database

Set `host_backend => 'postgresql'` and supply the database credentials. The module configures the `hosts-database` connection and loads the `libdhcp_host_cmds.so` hook automatically.

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  host_backend                => 'postgresql',
  host_sensitive_db_password  => Sensitive('HostDbP@ssw0rd!'),
  # Optional — defaults shown below
  host_database_name          => 'kea',
  host_database_user          => 'kea',
  host_database_host          => '127.0.0.1',
  host_database_port          => 5432,
}

kea_dhcp_v4_reservation { 'fileserver':
  ensure          => present,
  identifier_type => 'hw-address',
  identifier      => '00:11:22:33:44:55',
  ip_address      => '192.0.2.10',
}
```

> **Two-run bootstrap**: provider selection depends on whether `hosts-database` is present in `kea-dhcp4.conf` at the start of the Puppet run. On the **first run** after switching to `host_backend => 'postgresql'`, Puppet writes `hosts-database` to the config file but cannot yet apply reservations via the database (the Puppet feature `kea_host_database` was not active at catalogue compile time). A warning is emitted for each skipped reservation. On the **second run**, the feature is detected, the `unix_socket` provider is selected, and reservations are applied to the database.

#### Transitioning from inline to host database

If you previously used the default `json` provider and switch to `host_backend => 'postgresql'`, any inline reservations embedded in `kea-dhcp4.conf` are automatically removed when the server provider writes `hosts-database`. A warning identifies how many inline reservations were removed. Re-run Puppet a second time to re-create them via the database:

```
Warning: Kea_dhcp_v4_server[dhcp4]: removed 3 inline reservation(s) from
kea-dhcp4.conf; re-run Puppet to apply them via the hosts-database.
```

No manual cleanup is required — the transition is handled entirely by the module across two Puppet runs.

### Interface Configuration

By default the DHCPv4 server listens on all available interfaces. Use `array_dhcp4_listen_interfaces` to restrict this to specific interfaces, and `dhcp4_socket_type` to control the socket type.

#### Listen on all interfaces (default)

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
}
```

This produces the following in `kea-dhcp4.conf`:

```json
"interfaces-config": {
    "interfaces": [ "*" ]
}
```

#### Listen on specific interfaces

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password    => Sensitive('SecurePassword123!'),
  array_dhcp4_listen_interfaces  => ['enp5s0', 'enp6s0'],
}
```

#### Bind to a specific IP address on an interface

Kea accepts `interface/address` notation to bind to a single address on a multi-homed interface:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password    => Sensitive('SecurePassword123!'),
  array_dhcp4_listen_interfaces  => [
    'enp5s0/10.0.0.15',
    'enp6s0/10.10.0.15',
  ],
}
```

#### Set the socket type

Use `dhcp4_socket_type` to choose between raw and UDP sockets. Raw sockets are the default in Kea and handle traffic before the OS network stack; UDP sockets are useful when a relay agent is present:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password    => Sensitive('SecurePassword123!'),
  array_dhcp4_listen_interfaces  => ['enp5s0'],
  dhcp4_socket_type              => 'udp',
}
```

### Dynamic DNS (DDNS)

The module supports Kea's DHCP-DDNS integration, allowing automatic DNS updates when leases are assigned or released.

#### Basic DDNS Configuration

Enable DDNS by configuring both the DHCP server communication settings and the DDNS server itself:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  enable_ddns                 => true,

  # DHCPv4 server DDNS connectivity settings
  dhcp_ddns => {
    'enable-updates'  => true,
    'server-ip'       => '127.0.0.1',
    'server-port'     => 53001,
    'sender-ip'       => '',
    'sender-port'     => 0,
    'max-queue-size'  => 1024,
    'ncr-protocol'    => 'UDP',
    'ncr-format'      => 'JSON',
  },

  # DDNS server configuration
  ddns_ip_address             => '127.0.0.1',
  ddns_port                   => 53001,
  ddns_server_timeout         => 500,
  ddns_ncr_protocol           => 'UDP',
  ddns_ncr_format             => 'JSON',
}
```

#### DDNS with TSIG Authentication

TSIG keys authenticate DNS updates. Two variants are supported: `secret` (inline value) and `secret_file_content` (file-backed).

##### Inline secret

Pass the key material directly. Wrap the value in `Sensitive()` to prevent it from appearing in Puppet reports and logs:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  enable_ddns                 => true,

  dhcp_ddns => {
    'enable-updates' => true,
    'server-ip'      => '127.0.0.1',
    'server-port'    => 53001,
  },

  ddns_tsig_keys => [
    {
      'name'      => 'ddns-key',
      'algorithm' => 'HMAC-SHA256',
      'secret'    => Sensitive('LSWXnfkKZjdPJI5QxlpnfQ=='),
    },
  ],
}
```

##### File-backed secret

Use `secret_file_content` to have the module write the key material to a restricted file (`/etc/kea/tsig/<name>.tsig`, owned `root:kea`, mode `0640`). The `kea_ddns_server` resource receives a `secret-file` path instead of the inline value. This is recommended when the key material comes from Hiera eyaml or another secrets manager:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  enable_ddns                 => true,

  dhcp_ddns => {
    'enable-updates' => true,
    'server-ip'      => '127.0.0.1',
    'server-port'    => 53001,
  },

  ddns_tsig_keys => [
    {
      'name'                => 'ddns-key',
      'algorithm'           => 'HMAC-SHA256',
      'secret_file_content' => Sensitive('LSWXnfkKZjdPJI5QxlpnfQ=='),
    },
  ],
}
```

This creates `/etc/kea/tsig/ddns-key.tsig` before the `kea_ddns_server` resource is applied, with `show_diff => false` to suppress the content from Puppet reports.

##### Mixed keys

Both variants may be combined in a single `ddns_tsig_keys` array:

```puppet
ddns_tsig_keys => [
  {
    'name'      => 'inline-key',
    'algorithm' => 'HMAC-SHA256',
    'secret'    => Sensitive('abc123=='),
  },
  {
    'name'                => 'file-key',
    'algorithm'           => 'HMAC-SHA256',
    'secret_file_content' => Sensitive('LSWXnfkKZjdPJI5QxlpnfQ=='),
  },
],
```

#### DDNS Domain Configuration

Define forward and reverse DNS zones using `kea_ddns_domain` resources.

The `domain_name` parameter is a namevar, which means the resource title becomes the domain name unless you explicitly specify a different domain_name. This makes common cases more concise:

```puppet
# Resource title becomes the domain_name (recommended)
kea_ddns_domain { 'example.com.':
  ensure      => present,
  direction   => 'forward',
  key_name    => 'ddns-key',
  dns_servers => [
    {
      'ip-address' => '192.0.2.53',
      'port'       => 53,
    },
  ],
}

# Use alternate title with explicit domain_name
kea_ddns_domain { 'forward-zone':
  ensure      => present,
  domain_name => 'example.com.',
  direction   => 'forward',
  key_name    => 'ddns-key',
  dns_servers => [
    {
      'ip-address' => '192.0.2.53',
      'port'       => 53,
    },
  ],
}

# Reverse DNS zone using domain as title
kea_ddns_domain { '2.0.192.in-addr.arpa.':
  ensure      => present,
  direction   => 'reverse',
  dns_servers => [
    {
      'ip-address' => '192.0.2.53',
      'port'       => 53,
      'key-name'   => 'ddns-key',  # Override per-server
    },
  ],
}
```

#### DDNS Behavioral Parameters

Control DDNS behavior at the DHCPv4 server level:

```puppet
class { 'kea_dhcp':
  lease_sensitive_db_password => Sensitive('SecurePassword123!'),
  dhcp_ddns => {
    'enable-updates'                => true,
    'server-ip'                     => '127.0.0.1',
    'server-port'                   => 53001,

    # Behavioral settings
    'ddns-send-updates'             => true,
    'ddns-override-no-update'       => false,
    'ddns-override-client-update'   => false,
    'ddns-replace-client-name'      => 'never',
    'ddns-generated-prefix'         => 'myhost',
    'ddns-qualifying-suffix'        => '',
    'ddns-update-on-renew'          => false,
    'ddns-conflict-resolution-mode' => 'check-with-dhcid',
  },
}
```

The DDNS server configuration is managed centrally through the `kea_dhcp` class. The module automatically creates the `kea_ddns_server` resource when `enable_ddns` is true, following the same pattern as the DHCPv4 server configuration.

### Hiera Example

#### Inline reservations (default)

```yaml
---
kea_dhcp::lease_sensitive_db_password: ENC[PKCS7,...]
kea_dhcp::lease_backend_install_mode: 'instance'
kea_dhcp::array_dhcp4_listen_interfaces:
  - 'enp5s0'
  - 'enp6s0'
kea_dhcp::array_dhcp4_server_options:
  - name: 'domain-name-servers'
    data: '8.8.8.8, 8.8.4.4'
  - name: 'domain-name'
    data: 'example.org'
```

#### PostgreSQL host database

```yaml
---
kea_dhcp::lease_sensitive_db_password: ENC[PKCS7,...]
kea_dhcp::lease_backend_install_mode: 'instance'
kea_dhcp::host_backend: 'postgresql'
kea_dhcp::host_sensitive_db_password: ENC[PKCS7,...]
kea_dhcp::host_database_port: 5432
kea_dhcp::array_dhcp4_listen_interfaces:
  - 'enp5s0'
  - 'enp6s0'
```

#### DDNS with file-backed TSIG keys

Use `secret_file_content` in Hiera to store key material alongside other encrypted secrets. The module writes the key to a restricted file on disk so the value is never placed inline in `kea-dhcp-ddns.conf`:

```yaml
---
kea_dhcp::lease_sensitive_db_password: ENC[PKCS7,...]
kea_dhcp::enable_ddns: true
kea_dhcp::ddns_tsig_keys:
  - name: 'ddns-key'
    algorithm: 'HMAC-SHA256'
    secret_file_content: ENC[PKCS7,...]
kea_dhcp::dhcp_ddns:
  enable-updates: true
  server-ip: '127.0.0.1'
  server-port: 53001
```

## Reference

See the [REFERENCE.md](./REFERENCE.md) file for detailed parameter documentation.

## Limitations

* Only the PostgreSQL backend is currently supported
* RedHat-family only (RHEL 8-9, Rocky 8-9)
* DHCPv6 scope management is not yet implemented

## Development

If you'd like to make changes submit a pull request. Ground rules:

* Ensure changes pass `pdk validate` and `pdk test unit` before submitting
* Expand test coverage for new functionality
