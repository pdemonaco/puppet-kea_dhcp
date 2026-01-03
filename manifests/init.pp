# @summary Manages an instance of the Kea DHCP server
#
# @param sensitive_db_password
#  The password for the Kea PostgreSQL user, wrapped in a Sensitive type.
#  It is assumed that the user name is kea, however this can be changed in
#  the kea_dhcp::install::postgresql class if needed.
#
# @param enable_dhcp4
#   Whether to enable the DHCPv4 server
#
# @param enable_dhcp6
#   Whether to enable the DHCPv6 server
#
# @param enable_ddns
#   Whether to enable the DDNS server for DHCPv4
#
# @param enable_ctrl_agent
#   Whether to enable the control agent. The agent provides a REST API to
#   manage the Kea services on this node.
#
# @param backend
#   The backend type to use for storing leases and host reservations.
#   Might also contain other configuration information, depending on the
#   mood of the developer.
#
# @param array_dhcp4_server_options
#   An array of additional options to include in the DHCPv4 server configuration.
#   These options are treateds as the default options for all subnets managed by the server.
#
# @param lease_database_name
#   Name of the PostgreSQL database to use for leases if that backend is selected.
#
# @param lease_database_user
#   PostgreSQL user to connect to the lease database if that backend is selected.
#
# @param lease_database_host
#   Hostname or IP address of the PostgreSQL server if that backend is selected.
#
# @param lease_database_port
#   Port number of the PostgreSQL server if that backend is selected.
class kea_dhcp (
  Sensitive[String] $sensitive_db_password,
  Array[Hash] $array_dhcp4_server_options = [],
  Boolean $enable_dhcp4 = true,
  Boolean $enable_dhcp6 = false,
  Boolean $enable_ddns = true,
  Boolean $enable_ctrl_agent = true,
  Optional[String] $lease_database_name = 'kea',
  Optional[String] $lease_database_user = 'kea',
  Optional[String] $lease_database_host = '127.0.0.1',
  Optional[Stdlib::Port] $lease_database_port = 5432,
  Kea_Dhcp::Backends $backend = 'postgresql',
) {
  include kea_dhcp::install
  include kea_dhcp::config
  include kea_dhcp::service

  Class['kea_dhcp::install']
  -> Class['kea_dhcp::config']
  ~> Class['kea_dhcp::service']
}
