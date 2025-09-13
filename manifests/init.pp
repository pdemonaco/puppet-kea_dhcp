class kea_dhcp {
  include kea_dhcp::install
  include kea_dhcp::config
  include kea_dhcp::service
}
