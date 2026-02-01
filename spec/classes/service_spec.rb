# frozen_string_literal: true

require 'spec_helper'

describe 'kea_dhcp::service' do
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

      context 'with default parameters (dhcp4 and ddns enabled)' do
        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to contain_service('kea-dhcp4').with(
            ensure: 'running',
            enable: true,
          )
        end

        it do
          is_expected.to contain_service('kea-dhcp-ddns').with(
            ensure: 'running',
            enable: true,
          )
        end

        it { is_expected.not_to contain_service('kea-dhcp6') }
      end
    end
  end
end
