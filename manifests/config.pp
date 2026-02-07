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
# @param server_options
#   Array of additional options to include in the DHCPv4 server configuration.
#
# @param sensitive_db_password
#   Sensitive value containing the password for the lease database user.
#
# @param dhcp_ddns
#   Hash of DHCP-DDNS configuration settings to include in the DHCPv4 server configuration.
#
# @param backend
#   The backend type used for storing leases. Used to determine which hooks libraries to load.
class kea_dhcp::config (
  Stdlib::Absolutepath $config_path = '/etc/kea/kea-dhcp4.conf',
  String $lease_database_name = $kea_dhcp::lease_database_name,
  String $lease_database_user = $kea_dhcp::lease_database_user,
  String $lease_database_host = $kea_dhcp::lease_database_host,
  Integer $lease_database_port = $kea_dhcp::lease_database_port,
  Array[Hash] $server_options = $kea_dhcp::array_dhcp4_server_options,
  Optional[Hash] $dhcp_ddns = $kea_dhcp::dhcp_ddns,
  Sensitive[String] $sensitive_db_password = $kea_dhcp::sensitive_db_password,
  Kea_Dhcp::Backends $backend = $kea_dhcp::backend,
) {
  $hooks_libraries = $backend ? {
    'postgresql' => [{ 'library' => '/usr/lib64/kea/hooks/libdhcp_pgsql.so' }],
    default      => [],
  }

  $server_params = {
    ensure          => present,
    config_path     => $config_path,
    options         => $server_options,
    hooks_libraries => $hooks_libraries,
    lease_database  => {
      'type'     => 'postgresql',
      'name'     => $lease_database_name,
      'user'     => $lease_database_user,
      'password' => $sensitive_db_password,
      'host'     => $lease_database_host,
      'port'     => $lease_database_port,
    },
  }

  $final_params = $dhcp_ddns ? {
    undef   => $server_params,
    default => $server_params + { dhcp_ddns => $dhcp_ddns },
  }

  kea_dhcp_v4_server { 'dhcp4':
    * => $final_params,
  }
}
