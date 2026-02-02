# kea_dhcp

#### Table of Contents

1. [Description](#description)
2. [Setup - The basics of getting started with kea_dhcp](#setup)
    * [What kea_dhcp affects](#what-kea_dhcp-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with kea_dhcp](#beginning-with-kea_dhcp)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Limitations - OS compatibility, etc.](#limitations)
5. [Development - Guide for contributing to the module](#development)

## Description

The kea_dhcp module installs, configures, and manages the [ISC Kea DHCP](https://www.isc.org/kea/) server. It provisions a PostgreSQL backend for lease storage and provides custom types for managing DHCPv4 server configuration and subnet scopes.

## Setup

### What kea_dhcp affects

This module impacts three main areas:

#### 1 - Packages

The `isc-kea` package is installed from the official ISC Cloudsmith repository. Repository management is handled automatically for RedHat-family systems.

#### 2 - PostgreSQL Instance

A dedicated PostgreSQL instance is created for lease storage. The instance runs on port 5433 by default with the Kea schema initialized via `kea-admin db-init`.

#### 3 - Configuration

The module manages `/etc/kea/kea-dhcp4.conf` through custom resource types. Configuration changes are validated with `kea-dhcp4 -t` before being committed.

### Setup Requirements

* RedHat-family OS (RHEL 8-9, Rocky 8-9)
* The `puppetlabs/postgresql` module for database provisioning

### Beginning with kea_dhcp

A minimal declaration requires only the database password:

```puppet
class { 'kea_dhcp':
  sensitive_db_password => Sensitive('SecurePassword123!'),
}
```

## Usage

### Server with Global Options

Configure the DHCPv4 server with default options applied to all subnets:

```puppet
class { 'kea_dhcp':
  sensitive_db_password      => Sensitive('SecurePassword123!'),
  array_dhcp4_server_options => [
    { 'name' => 'routers', 'data' => '192.0.2.1' },
  ],
  enable_ddns                => false,
  enable_ctrl_agent          => false,
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

Reserve specific IP addresses for known hosts using `kea_dhcp_v4_reservation`. The subnet is automatically detected from the IP address:

```puppet
# Reserve using MAC address
kea_dhcp_v4_reservation { 'file-server':
  ensure          => present,
  identifier_type => 'hw-address',
  identifier      => '00:11:22:33:44:55',
  ip_address      => '192.0.2.10',
  hostname        => 'fileserver',
}

# Reserve using client-id
kea_dhcp_v4_reservation { 'printer':
  ensure          => present,
  identifier_type => 'client-id',
  identifier      => '01:aa:bb:cc:dd:ee:ff',
  ip_address      => '192.0.2.20',
  hostname        => 'printer-1',
}

# Reservation without hostname
kea_dhcp_v4_reservation { 'laptop':
  ensure          => present,
  identifier_type => 'hw-address',
  identifier      => 'a1:b2:c3:d4:e5:f6',
  ip_address      => '192.0.2.30',
}
```

The provider automatically finds the correct subnet by matching the IP address against configured subnet ranges. You can also explicitly specify the subnet using `scope_id` if needed.

Uniqueness is enforced within each subnet - duplicate identifiers, IP addresses, or hostnames will be rejected.

### Hiera Example

```yaml
---
kea_dhcp::sensitive_db_password: ENC[PKCS7,...]
kea_dhcp::array_dhcp4_server_options:
  - name: 'domain-name-servers'
    data: '8.8.8.8, 8.8.4.4'
  - name: 'domain-name'
    data: 'example.org'
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
