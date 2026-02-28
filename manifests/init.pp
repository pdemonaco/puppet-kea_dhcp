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
# @param array_dhcp4_listen_interfaces
#   List of interfaces the DHCPv4 server listens on. Use ['*'] for all interfaces.
#   Entries may optionally include an IP address (e.g. 'eth0/10.0.0.1').
#
# @param dhcp4_socket_type
#   Socket type used for DHCPv4 communication. Either 'raw' or 'udp'.
#
# @param array_dhcp4_server_options
#   An array of additional options to include in the DHCPv4 server configuration.
#   These options are treateds as the default options for all subnets managed by the server.
#
# @param dhcp_ddns
#   Hash of DHCP-DDNS configuration settings to include in the DHCPv4 server configuration.
#   These settings control how the DHCPv4 server communicates with the DDNS server.
#
# @param ddns_ip_address
#   IP address on which the DDNS server listens for requests.
#
# @param ddns_port
#   Port on which the DDNS server listens for requests.
#
# @param ddns_server_timeout
#   Maximum time to wait for DNS server response in milliseconds.
#
# @param ddns_ncr_protocol
#   Protocol for DDNS server communication (UDP or TCP).
#
# @param ddns_ncr_format
#   Format for DDNS server communication (JSON).
#
# @param ddns_tsig_keys
#   Array of TSIG key configurations for DNS update authentication.
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
#
# @param lease_backend_install_mode
#   Controls how the lease database backend is installed.
#   - 'instance': Create a dedicated PostgreSQL instance (default)
#   - 'database': Add the Kea database to the existing default instance
#   - 'none': Skip database installation (database is managed externally)
#
class kea_dhcp (
  Sensitive[String] $sensitive_db_password,
  Array[String] $array_dhcp4_listen_interfaces = ['*'],
  Optional[Enum['raw', 'udp']] $dhcp4_socket_type = undef,
  Array[Hash] $array_dhcp4_server_options = [],
  Optional[Hash] $dhcp_ddns = undef,
  Boolean $enable_dhcp4 = true,
  Boolean $enable_dhcp6 = false,
  Boolean $enable_ddns = true,
  Boolean $enable_ctrl_agent = true,
  Stdlib::IP::Address::V4 $ddns_ip_address = '127.0.0.1',
  Stdlib::Port $ddns_port = 53001,
  Integer[1] $ddns_server_timeout = 500,
  Enum['UDP', 'TCP'] $ddns_ncr_protocol = 'UDP',
  Enum['JSON'] $ddns_ncr_format = 'JSON',
  Array[Hash] $ddns_tsig_keys = [],
  String $lease_database_name = 'kea',
  String $lease_database_user = 'kea',
  Stdlib::Host $lease_database_host = '127.0.0.1',
  Stdlib::Port $lease_database_port = 5433,
  Kea_Dhcp::Backends $backend = 'postgresql',
  Kea_Dhcp::Db_install_mode $lease_backend_install_mode = 'instance',
) {
  include kea_dhcp::install
  include kea_dhcp::config
  include kea_dhcp::service

  Class['kea_dhcp::install']
  -> Class['kea_dhcp::config']
  ~> Class['kea_dhcp::service']
}
