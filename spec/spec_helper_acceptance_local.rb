# frozen_string_literal: true

require 'singleton'

class LitmusHelper
  include Singleton
  include PuppetLitmus
end

def install_repository
  pp = <<-MANIFEST
    yumrepo { 'isc-kea-3-0':
        ensure          => present,
        descr           => 'ISC - kea-3-0',
        baseurl         => 'https://dl.cloudsmith.io/public/isc/kea-3-0/rpm/el/$releasever/$basearch',
        enabled         => 1,
        gpgcheck        => 1,
        repo_gpgcheck   => 1,
        gpgkey          => 'https://dl.cloudsmith.io/public/isc/kea-3-0/gpg.B16C44CD45514C3C.key',
        sslverify       => 1,
        sslcacert       => '/etc/pki/tls/certs/ca-bundle.crt',
        metadata_expire => 300,
    }
    
    yumrepo { 'isc-kea-3-0-noarch':
      name                => 'isc-kea-3-0-noarch',
      baseurl             => 'https://dl.cloudsmith.io/public/isc/kea-3-0/rpm/el/9/noarch',
      enabled             => 1,
      gpgcheck            => 1,
      repo_gpgcheck       => 1,
      gpgkey              => 'https://dl.cloudsmith.io/public/isc/kea-3-0/gpg.B16C44CD45514C3C.key',
      sslverify           => 1,
      sslcacert           => '/etc/pki/tls/certs/ca-bundle.crt',
      metadata_expire     => 300,
    }
    
    yumrepo { 'PGDG-common':
        ensure  => present,
        descr   => 'PostgreSQL common repository',
        baseurl => 'https://download.postgresql.org/pub/repos/yum/common/redhat/rhel-$releasever-$basearch',
        enabled => 1,
        gpgcheck => 1,
        gpgkey  => 'https://download.postgresql.org/pub/repos/yum/RPM-GPG-KEY-PGDG',
    }

    yumrepo { 'PGDG-16':
        ensure  => present,
        descr   => 'PostgreSQL 16 for RHEL $releasever - $basearch',
        baseurl => 'https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-$releasever-$basearch',
        enabled => 1,
        gpgcheck => 1,
        gpgkey  => 'https://download.postgresql.org/pub/repos/yum/RPM-GPG-KEY-PGDG',
    }
    
    include 'yum'
    class { 'yum':
      managed_repos => ['epel'],
    }
  MANIFEST
  LitmusHelper.instance.apply_manifest(pp, expect_failures: false)
end