# @summary Installs all dependencies of the isc-kea application
#
# @param backend
#   The backend type to use for storing leases and host reservations.
class kea_dhcp::install (
  Kea_Dhcp::Backends $backend = $kea_dhcp::backend,
) {
  # log4cplus is required by isc-kea-common and is available in EPEL
  package { 'log4cplus':
    ensure => installed,
  }

  package { 'isc-kea':
    ensure  => installed,
    require => Package['log4cplus'],
  }

  case $backend {
    'postgresql': {
      include 'kea_dhcp::install::postgresql'
      package { 'isc-kea-pgsql':
        ensure => installed,
      }
    }
    default: {
      fail("Unsupported backend type ${backend}")
    }
  }

  if $facts['os']['family'] == 'RedHat' {
    include 'kea_dhcp::install::yum_isc_repos'
    Class['kea_dhcp::install::yum_isc_repos'] -> Package['isc-kea']
    Class['kea_dhcp::install::yum_isc_repos'] -> Package['isc-kea-pgsql']

    # log4cplus comes from EPEL, ensure it's available before isc-kea
    Package['log4cplus'] -> Package['isc-kea']
  }
}
