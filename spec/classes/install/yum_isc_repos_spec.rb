# frozen_string_literal: true

require 'spec_helper'

describe 'kea_dhcp::install::yum_isc_repos' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      it do
        is_expected.to contain_yumrepo('isc-kea-3-0').with(
          ensure: 'present',
          descr: 'ISC - Kea-3-0',
          baseurl: 'https://dl.cloudsmith.io/public/isc/kea-3-0/rpm/el/$releasever/$basearch',
          enabled: 1,
          gpgcheck: 1,
          repo_gpgcheck: 1,
          gpgkey: 'https://dl.cloudsmith.io/public/isc/kea-3-0/gpg.B16C44CD45514C3C.key',
          sslverify: 1,
          sslcacert: '/etc/pki/tls/certs/ca-bundle.crt',
          metadata_expire: '300',
        )
      end

      it do
        is_expected.to contain_yumrepo('isc-kea-3-0-noarch').with(
          ensure: 'present',
          descr: 'ISC - Kea-3-0 - Noarch',
          baseurl: 'https://dl.cloudsmith.io/public/isc/kea-3-0/rpm/el/$releasever/noarch',
          enabled: 1,
          gpgcheck: 1,
          repo_gpgcheck: 1,
          gpgkey: 'https://dl.cloudsmith.io/public/isc/kea-3-0/gpg.B16C44CD45514C3C.key',
          sslverify: 1,
          sslcacert: '/etc/pki/tls/certs/ca-bundle.crt',
          metadata_expire: '300',
        )
      end
    end
  end
end
