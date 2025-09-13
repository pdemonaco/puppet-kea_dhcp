# @summary Manages the Kea DHCP services
#
# @param enable_dhcp4
#   Whether to manage the kea-dhcp4 service
#
# @param enable_dhcp6
#   Whether to manage the kea-dhcp6 service
#
# @param enable_ddns
#   Whether to manage the kea-dhcp-ddns service
#
# @param enable_ctrl_agent
#   Whether to manage the kea-ctrl-agent service
#
# @param dhcp4_service_name
#   The name of the kea-dhcp4 service for this OS.
#
# @param dhcp6_service_name
#   The name of the kea-dhcp6 service for this OS.
#
# @param ddns_service_name
#   The name of the kea-dhcp-ddns service for this OS.
#
# @param ctrl_agent_service_name
#   The name of the kea-ctrl-agent service for this OS.
class kea_dhcp::service (
  String $dhcp4_service_name,
  String $dhcp6_service_name,
  String $ddns_service_name,
  String $ctrl_agent_service_name,
  Boolean $enable_dhcp4 = $kea_dhcp::enable_dhcp4,
  Boolean $enable_dhcp6 = $kea_dhcp::enable_dhcp6,
  Boolean $enable_ddns = $kea_dhcp::enable_ddns,
  Boolean $enable_ctrl_agent = $kea_dhcp::enable_ctrl_agent,
) {
  if $enable_ctrl_agent {
    service { $ctrl_agent_service_name:
      ensure => running,
      enable => true,
    }
  }
  if $enable_dhcp4 {
    service { $dhcp4_service_name:
      ensure => running,
      enable => true,
    }
  }
  if $enable_dhcp6 {
    service { $dhcp6_service_name:
      ensure => running,
      enable => true,
    }
  }
  if $enable_ddns {
    service { $ddns_service_name:
      ensure => running,
      enable => true,
    }
  }
}
