# @summary Installs all dependencies of the isc-kea application
#
# @param backend
#   The backend type to use for storing leases and host reservations.
class kea_dhcp::install (
  Kea_Dhcp::Backends $backend = $kea_dhcp::backend,
) {
  package { 'isc-kea':
    ensure => installed,
  }

  case $backend {
    'postgresql': {
      include kea_dhcp::install::postgresql
    }
    default: {
      fail("Unsupported backend type ${backend}")
    }
  }
}
