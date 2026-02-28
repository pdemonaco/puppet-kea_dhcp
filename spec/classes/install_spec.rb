# frozen_string_literal: true

require 'spec_helper'

describe 'kea_dhcp::install' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with default install_mode (instance)' do
        let(:pre_condition) do
          <<-PUPPET
            class { 'kea_dhcp':
              lease_sensitive_db_password => Sensitive('test_password'),
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        it { is_expected.to contain_package('isc-kea').with(ensure: 'installed') }
        it { is_expected.to contain_package('isc-kea-pgsql').with(ensure: 'installed') }
        it { is_expected.to contain_package('log4cplus').with(ensure: 'installed') }

        it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos') }
        it { is_expected.to contain_class('kea_dhcp::install::postgresql') }

        it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos').that_comes_before('Package[isc-kea]') }
        it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos').that_comes_before('Package[isc-kea-pgsql]') }

        it { is_expected.to contain_postgresql__server_instance('kea') }
        it { is_expected.to contain_postgresql__server__db('kea') }
        it { is_expected.to contain_exec('init_kea_dhcp_schema') }
        it { is_expected.to contain_yumrepo('isc-kea-3-0') }
        it { is_expected.to contain_yumrepo('isc-kea-3-0-noarch') }
        it { is_expected.to contain_class('kea_dhcp::config') }
        it { is_expected.to contain_class('kea_dhcp::service') }
        it { is_expected.to contain_kea_dhcp_v4_server('dhcp4') }
        it { is_expected.to contain_kea_ddns_server('dhcp-ddns') }
        it { is_expected.to contain_service('kea-dhcp4') }
        it { is_expected.to contain_service('kea-dhcp-ddns') }
      end

      context 'with install_mode => database' do
        let(:pre_condition) do
          <<-PUPPET
            class { 'kea_dhcp':
              lease_sensitive_db_password      => Sensitive('test_password'),
              lease_backend_install_mode => 'database',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('isc-kea-pgsql').with(ensure: 'installed') }
        it { is_expected.to contain_class('kea_dhcp::install::postgresql') }
        it { is_expected.not_to contain_postgresql__server_instance('kea') }
        it { is_expected.to contain_postgresql__server__db('kea') }
        it { is_expected.to contain_exec('init_kea_dhcp_schema') }
      end

      context 'with install_mode => none' do
        let(:pre_condition) do
          <<-PUPPET
            class { 'kea_dhcp':
              lease_sensitive_db_password      => Sensitive('test_password'),
              lease_backend_install_mode => 'none',
            }
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('isc-kea-pgsql').with(ensure: 'installed') }
        it { is_expected.not_to contain_class('kea_dhcp::install::postgresql') }
        it { is_expected.not_to contain_postgresql__server_instance('kea') }
        it { is_expected.not_to contain_exec('init_kea_dhcp_schema') }
      end
    end
  end
end
