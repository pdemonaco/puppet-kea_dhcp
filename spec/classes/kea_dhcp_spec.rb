# frozen_string_literal: true

require 'spec_helper'
require 'deep_merge'

describe 'kea_dhcp' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) do
        resolved_facts = os_facts.dup

        os_fact = resolved_facts['os'] || resolved_facts[:os]
        if !os_fact.is_a?(Hash) || !(os_fact['family'] || os_fact[:family])
          os_name = resolved_facts['operatingsystem'] || resolved_facts[:operatingsystem]
          os_family = resolved_facts['osfamily'] || resolved_facts[:osfamily]
          os_release_full = resolved_facts['operatingsystemrelease'] || resolved_facts[:operatingsystemrelease]
          os_release_major = resolved_facts['operatingsystemmajrelease'] || resolved_facts[:operatingsystemmajrelease]
          os_release_major ||= os_release_full&.split('.')&.first

          structured_os = {}
          structured_os['name'] = os_name if os_name
          structured_os['family'] = os_family if os_family

          release = {}
          release['full'] = os_release_full if os_release_full
          release['major'] = os_release_major if os_release_major
          structured_os['release'] = release unless release.empty?

          unless structured_os.empty?
            resolved_facts['os'] = structured_os
            resolved_facts[:os] = structured_os
          end
        end
        resolved_facts
      end

      let(:params) do
        {
          sensitive_db_password: RSpec::Puppet::RawString.new("Sensitive('kea_password')"),
        }
      end

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_class('Kea_dhcp::Install').with_before(['Class[Kea_dhcp::Config]']) }
      it {
        is_expected.to contain_class('kea_dhcp::config').with(
          notify: ['Class[Kea_dhcp::Service]'],
        )
      }
      it { is_expected.to contain_class('kea_dhcp::service') }

      it 'manages the DHCPv4 server configuration' do
        is_expected.to contain_kea_dhcp_v4_server('dhcp4').with(
          'ensure' => 'present',
          'config_path' => '/etc/kea/kea-dhcp4.conf',
          'options' => [],
        )

        lease_database = catalogue.resource('Kea_dhcp_v4_server', 'dhcp4')[:lease_database]

        expect(lease_database).to include(
          'type' => 'postgresql',
          'name' => 'kea',
          'user' => 'kea',
          'host' => '127.0.0.1',
          'port' => 5433,
        )
        expect(lease_database['password']).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(lease_database['password'].unwrap).to eq('kea_password')
      end

      context 'with PostgreSQL setup' do
        it 'configures the server instance' do
          is_expected.to contain_postgresql__server_instance('kea').with(
            'config_settings' => {
              'pg_hba_conf_path' => '/opt/pgsql/data/kea/pg_hba.conf',
              'postgresql_conf_path' => '/opt/pgsql/data/kea/postgresql.conf',
              'pg_ident_conf_path' => '/opt/pgsql/data/kea/pg_ident.conf',
              'datadir' => '/opt/pgsql/data/kea',
              'service_name' => 'postgresql@kea',
              'port' => 5433,
            },
            'service_settings' => {
              'service_name' => 'postgresql@kea',
              'service_status' => 'systemctl status postgresql@kea.service',
              'service_enable' => true,
              'service_ensure' => 'running',
            },
            'initdb_settings' => {
              'datadir' => '/opt/pgsql/data/kea',
              'group' => 'postgres',
              'user' => 'postgres',
            },
          )
        end

        it 'creates the application database' do
          is_expected.to contain_postgresql__server__db('kea').with(
            'user' => 'kea',
            'instance' => 'kea',
            'require' => 'Postgresql::Server_instance[kea]',
          )

          db_resource = catalogue.resource('Postgresql::Server::Db', 'kea')
          password = db_resource[:password]

          if password.is_a?(Puppet::Pops::Types::PSensitiveType::Sensitive)
            expect(password.unwrap).to eq('kea_password')
          else
            expect(password).to eq('kea_password')
          end
        end

        it 'initializes the schema' do
          is_expected.to contain_exec('init_kea_dhcp_schema').with(
            'command' => "/usr/sbin/kea-admin db-init pgsql -u kea -p \"\${PGPASSWORD}\" -h 127.0.0.1 -P 5433 -n kea",
            'environment' => [
              'PGPASSWORD=kea_password',
            ],
            'user' => 'postgres',
          ).that_requires('Postgresql::Server::Db[kea]')
        end
      end
    end
  end
end
