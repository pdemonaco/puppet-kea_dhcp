# @summary Manages the YUM repositories for ISC Kea on RedHat-based systems
#
# @param base_url
#   The base URL for the ISC Cloudsmith repository.
class kea_dhcp::install::yum_isc_repos (
  Stdlib::HttpUrl $base_url = 'https://dl.cloudsmith.io/public/isc',
) {
  $major_release = '3-0'
  $key_id        = 'B16C44CD45514C3C'
  yumrepo { "isc-kea-${major_release}":
    ensure          => present,
    descr           => "ISC - Kea-${major_release}",
    baseurl         => "${base_url}/kea-${major_release}/rpm/el/\$releasever/\$basearch",
    enabled         => 1,
    gpgcheck        => 1,
    repo_gpgcheck   => 1,
    gpgkey          => "${base_url}/kea-${major_release}/rpm/gpg.${key_id}.key",
    sslverify       => 1,
    sslcacert       => '/etc/pki/tls/certs/ca-bundle.crt',
    metadata_expire => '300',
  }
  yumrepo { "isc-kea-${major_release}":
    ensure          => present,
    descr           => "ISC - Kea-${major_release} - Noarch",
    baseurl         => "${base_url}/kea-${major_release}/rpm/el/\$releasever/noarch",
    enabled         => 1,
    gpgcheck        => 1,
    repo_gpgcheck   => 1,
    gpgkey          => "${base_url}/kea-${major_release}/rpm/gpg.${key_id}.key",
    sslverify       => 1,
    sslcacert       => '/etc/pki/tls/certs/ca-bundle.crt',
    metadata_expire => '300',
  }
}
