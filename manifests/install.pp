# @summary Installs all dependencies of the isc-kea application
#
# @param lease_backend
#   The backend type to use for storing leases.
# @param install_mode
#   Controls how the lease database backend is installed.
class kea_dhcp::install (
  Kea_Dhcp::Backends $lease_backend = $kea_dhcp::lease_backend,
  Kea_Dhcp::Db_install_mode $install_mode = $kea_dhcp::lease_backend_install_mode,
) {
  # log4cplus is required by isc-kea-common and is available in EPEL
  package { 'log4cplus':
    ensure => installed,
  }

  package { 'isc-kea':
    ensure  => installed,
    require => Package['log4cplus'],
  }

  case $lease_backend {
    'postgresql': {
      if $install_mode != 'none' {
        include 'kea_dhcp::install::postgresql'
      }
      package { 'isc-kea-pgsql':
        ensure => installed,
      }
    }
    default: {
      fail("Unsupported lease backend type ${lease_backend}")
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
