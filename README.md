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

The kea_dhcp module installs, configures, and manages the [ISC Kea DHCP](https://www.isc.org/kea/) server. It provisions a PostgreSQL backend for lease storage and provides custom types for managing DHCPv4 server configuration, subnet scopes, host reservations, and Dynamic DNS (DDNS) integration.

## Setup

### What kea_dhcp affects

This module impacts three main areas:

#### 1 - Packages

The `isc-kea` package is installed from the official ISC Cloudsmith repository. Repository management is handled automatically for RedHat-family systems.

#### 2 - PostgreSQL Instance

A dedicated PostgreSQL instance is created for lease storage. The instance runs on port 5433 by default with the Kea schema initialized via `kea-admin db-init`.

#### 3 - Configuration

The module manages `/etc/kea/kea-dhcp4.conf` and `/etc/kea/kea-dhcp-ddns.conf` through custom resource types. Configuration changes are validated with `kea-dhcp4 -t` and `kea-dhcp-ddns -t` respectively before being committed.

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

### Dynamic DNS (DDNS)

The module supports Kea's DHCP-DDNS integration, allowing automatic DNS updates when leases are assigned or released.

#### Basic DDNS Configuration

Enable DDNS by configuring both the DHCP server communication settings and the DDNS server itself:

```puppet
class { 'kea_dhcp':
  sensitive_db_password => Sensitive('SecurePassword123!'),
  enable_ddns          => true,

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
  ddns_ip_address      => '127.0.0.1',
  ddns_port            => 53001,
  ddns_server_timeout  => 500,
  ddns_ncr_protocol    => 'UDP',
  ddns_ncr_format      => 'JSON',
}
```

#### DDNS with TSIG Authentication

Use TSIG keys to authenticate DNS updates:

```puppet
class { 'kea_dhcp':
  sensitive_db_password => Sensitive('SecurePassword123!'),
  enable_ddns          => true,

  dhcp_ddns => {
    'enable-updates' => true,
    'server-ip'      => '127.0.0.1',
    'server-port'    => 53001,
  },

  ddns_tsig_keys => [
    {
      'name'      => 'ddns-key',
      'algorithm' => 'HMAC-SHA256',
      'secret'    => 'LSWXnfkKZjdPJI5QxlpnfQ==',
    },
  ],
}
```

#### DDNS Domain Configuration

Define forward and reverse DNS zones using `kea_ddns_domain` resources:

```puppet
# Forward DNS zone
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

# Reverse DNS zone
kea_ddns_domain { 'reverse-zone':
  ensure      => present,
  domain_name => '2.0.192.in-addr.arpa.',
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
  sensitive_db_password => Sensitive('SecurePassword123!'),
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
