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
class kea_dhcp (
  Sensitive[String] $sensitive_db_password,
  Boolean $enable_dhcp4 = true,
  Boolean $enable_dhcp6 = false,
  Boolean $enable_ddns = true,
  Boolean $enable_ctrl_agent = true,
  Kea_Dhcp::Backends $backend = 'postgresql',
) {
  include kea_dhcp::install
  include kea_dhcp::config
  include kea_dhcp::service

  Class['kea_dhcp::install']
  -> Class['kea_dhcp::config']
  ~> Class['kea_dhcp::service']
}
