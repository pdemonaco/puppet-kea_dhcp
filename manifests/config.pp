# Summary Configuration of the kea DHCP server application
#
# @param config_path
#   Path to the main kea-dhcp4 configuration file.
#
# @param lease_database_name
#   Name of the PostgreSQL database to use for leases.
#
# @param lease_database_user
#   PostgreSQL user to connect to the lease database.
#
# @param lease_database_host
#   Hostname or IP address of the PostgreSQL server.
#
# @param lease_database_port
#   Port number of the PostgreSQL server
#
# @param listen_interfaces
#   List of interfaces the DHCPv4 server listens on.
#
# @param dhcp4_socket_type
#   Socket type for DHCPv4 communication ('raw' or 'udp').
#
# @param server_options
#   Array of additional options to include in the DHCPv4 server configuration.
#
# @param lease_sensitive_db_password
#   Sensitive value containing the password for the lease database user.
#
# @param dhcp_ddns
#   Hash of DHCP-DDNS configuration settings to include in the DHCPv4 server configuration.
#
# @param enable_ddns
#   Whether to configure the DDNS server.
#
# @param ddns_ip_address
#   IP address on which the DDNS server listens.
#
# @param ddns_port
#   Port on which the DDNS server listens.
#
# @param ddns_server_timeout
#   DNS server timeout in milliseconds.
#
# @param ddns_ncr_protocol
#   DDNS communication protocol.
#
# @param ddns_ncr_format
#   DDNS communication format.
#
# @param ddns_qualifying_suffix
#   Qualifying suffix appended to partial domain names for DDNS updates. Optional.
#
# @param ddns_update_on_renew
#   When true, update DNS on lease renewal even if FQDN is unchanged. Optional.
#
# @param ddns_tsig_keys
#   TSIG keys for DNS authentication.
#
# @param lease_backend
#   The backend type used for storing leases. Used to determine which hooks libraries to load.
#
# @param host_backend
#   The backend type used for host reservations. When 'postgresql', configures the
#   host-database connection and loads the libdhcp_host_cmds.so hook.
#
# @param host_sensitive_db_password
#   Sensitive value containing the password for the host database user.
#
# @param host_database_name
#   Name of the PostgreSQL database for host reservations.
#
# @param host_database_user
#   PostgreSQL user for the host database.
#
# @param host_database_host
#   Hostname or IP address of the host database server.
#
# @param host_database_port
#   Port number of the host database server.
#
class kea_dhcp::config (
  Stdlib::Absolutepath $config_path = '/etc/kea/kea-dhcp4.conf',
  String $lease_database_name = $kea_dhcp::lease_database_name,
  String $lease_database_user = $kea_dhcp::lease_database_user,
  Stdlib::Host $lease_database_host = $kea_dhcp::lease_database_host,
  Integer $lease_database_port = $kea_dhcp::lease_database_port,
  Array[String] $listen_interfaces = $kea_dhcp::array_dhcp4_listen_interfaces,
  Optional[Enum['raw', 'udp']] $dhcp4_socket_type = $kea_dhcp::dhcp4_socket_type,
  Array[Hash] $server_options = $kea_dhcp::array_dhcp4_server_options,
  Optional[Hash] $dhcp_ddns = $kea_dhcp::dhcp_ddns,
  Sensitive[String] $lease_sensitive_db_password = $kea_dhcp::lease_sensitive_db_password,
  Boolean $enable_ddns = $kea_dhcp::enable_ddns,
  Stdlib::IP::Address::V4 $ddns_ip_address = $kea_dhcp::ddns_ip_address,
  Stdlib::Port $ddns_port = $kea_dhcp::ddns_port,
  Integer[1] $ddns_server_timeout = $kea_dhcp::ddns_server_timeout,
  Enum['UDP', 'TCP'] $ddns_ncr_protocol = $kea_dhcp::ddns_ncr_protocol,
  Enum['JSON'] $ddns_ncr_format = $kea_dhcp::ddns_ncr_format,
  Optional[Stdlib::Fqdn] $ddns_qualifying_suffix = $kea_dhcp::ddns_qualifying_suffix,
  Optional[Boolean] $ddns_update_on_renew = $kea_dhcp::ddns_update_on_renew,
  Array[Kea_Dhcp::TsigKey] $ddns_tsig_keys = $kea_dhcp::ddns_tsig_keys,
  Kea_Dhcp::Backends $lease_backend = $kea_dhcp::lease_backend,
  Enum['postgresql', 'json'] $host_backend = $kea_dhcp::host_backend,
  Optional[Sensitive[String]] $host_sensitive_db_password = $kea_dhcp::host_sensitive_db_password,
  String $host_database_name = $kea_dhcp::host_database_name,
  String $host_database_user = $kea_dhcp::host_database_user,
  Stdlib::Host $host_database_host = $kea_dhcp::host_database_host,
  Integer $host_database_port = $kea_dhcp::host_database_port,
) {
  $lease_hooks = $lease_backend ? {
    'postgresql' => [{ 'library' => '/usr/lib64/kea/hooks/libdhcp_pgsql.so' }],
    default      => [],
  }

  $lease_cmd_hooks = [{ 'library' => '/usr/lib64/kea/hooks/libdhcp_lease_cmds.so' }]

  $host_hooks = $host_backend ? {
    'postgresql' => [{ 'library' => '/usr/lib64/kea/hooks/libdhcp_host_cmds.so' }],
    default      => [],
  }

  $hooks_libraries = $lease_hooks + $host_hooks + $lease_cmd_hooks

  $base_interfaces_config = { 'interfaces' => $listen_interfaces }
  $interfaces_config = $dhcp4_socket_type ? {
    undef   => $base_interfaces_config,
    default => $base_interfaces_config + { 'dhcp-socket-type' => $dhcp4_socket_type },
  }

  $base_server_params = {
    ensure            => present,
    config_path       => $config_path,
    options           => $server_options,
    hooks_libraries   => $hooks_libraries,
    interfaces_config => $interfaces_config,
    lease_database    => {
      'type'     => 'postgresql',
      'name'     => $lease_database_name,
      'user'     => $lease_database_user,
      'password' => $lease_sensitive_db_password,
      'host'     => $lease_database_host,
      'port'     => $lease_database_port,
    },
  }

  $host_database = $host_backend ? {
    'postgresql' => {
      'type'     => 'postgresql',
      'name'     => $host_database_name,
      'user'     => $host_database_user,
      'password' => $host_sensitive_db_password,
      'host'     => $host_database_host,
      'port'     => $host_database_port,
    },
    default => undef,
  }

  $with_host_db = $host_database ? {
    undef   => $base_server_params,
    default => $base_server_params + { host_database => $host_database },
  }

  $with_ddns_conn = $dhcp_ddns ? {
    undef   => $with_host_db,
    default => $with_host_db + { dhcp_ddns => $dhcp_ddns },
  }

  $with_qs = $ddns_qualifying_suffix ? {
    undef   => $with_ddns_conn,
    default => $with_ddns_conn + { ddns_qualifying_suffix => $ddns_qualifying_suffix },
  }

  $final_params = $ddns_update_on_renew ? {
    undef   => $with_qs,
    default => $with_qs + { ddns_update_on_renew => $ddns_update_on_renew },
  }

  kea_dhcp_v4_server { 'dhcp4':
    * => $final_params,
  }

  $tsig_key_dir = '/etc/kea/tsig'
  $tsig_file_key_entries = $ddns_tsig_keys.filter |$key| { 'secret_file_content' in $key }

  if $enable_ddns and !$tsig_file_key_entries.empty() {
    file { $tsig_key_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'kea',
      mode   => '0750',
      before => Kea_ddns_server['dhcp-ddns'],
    }

    $tsig_file_key_entries.each |$key| {
      $key_name = $key['name']
      file { "${tsig_key_dir}/${key_name}.tsig":
        ensure    => file,
        owner     => 'root',
        group     => 'kea',
        mode      => '0640',
        content   => $key['secret_file_content'],
        show_diff => false,
        require   => File[$tsig_key_dir],
        before    => Kea_ddns_server['dhcp-ddns'],
      }
    }
  }

  $processed_tsig_keys = $ddns_tsig_keys.map |$key| {
    if 'secret_file_content' in $key {
      {
        'name'        => $key['name'],
        'algorithm'   => $key['algorithm'],
        'secret-file' => "${tsig_key_dir}/${key['name']}.tsig",
      }
    } else {
      $key
    }
  }

  if $enable_ddns {
    kea_ddns_server { 'dhcp-ddns':
      ensure             => present,
      ip_address         => $ddns_ip_address,
      port               => $ddns_port,
      dns_server_timeout => $ddns_server_timeout,
      ncr_protocol       => $ddns_ncr_protocol,
      ncr_format         => $ddns_ncr_format,
      tsig_keys          => $processed_tsig_keys,
    }
  }
}
