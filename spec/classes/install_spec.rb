# frozen_string_literal: true

require 'spec_helper'

describe 'kea_dhcp::install' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:pre_condition) do
        <<-PUPPET
          class { 'kea_dhcp':
            sensitive_db_password => Sensitive('test_password'),
          }
        PUPPET
      end

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_package('isc-kea').with(ensure: 'installed') }
      it { is_expected.to contain_package('isc-kea-pgsql').with(ensure: 'installed') }

      it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos') }
      it { is_expected.to contain_class('kea_dhcp::install::postgresql') }

      it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos').that_comes_before('Package[isc-kea]') }
      it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos').that_comes_before('Package[isc-kea-pgsql]') }
    end
  end
end
