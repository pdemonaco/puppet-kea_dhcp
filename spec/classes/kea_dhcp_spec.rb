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
          lease_sensitive_db_password: RSpec::Puppet::RawString.new("Sensitive('kea_password')"),
        }
      end

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_class('kea_dhcp::install::postgresql') }
      it { is_expected.to contain_class('kea_dhcp::install::yum_isc_repos') }
      it { is_expected.to contain_package('isc-kea') }
      it { is_expected.to contain_package('isc-kea-pgsql') }
      it { is_expected.to contain_package('log4cplus') }
      it { is_expected.to contain_service('kea-dhcp4') }
      it { is_expected.to contain_service('kea-dhcp-ddns') }
      it { is_expected.to contain_yumrepo('isc-kea-3-0') }
      it { is_expected.to contain_yumrepo('isc-kea-3-0-noarch') }

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
          'interfaces_config' => { 'interfaces' => ['*'] },
          'valid_lifetime' => 3600,
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

      context 'with valid_lifetime set' do
        let(:params) do
          super().merge(valid_lifetime: 86_000)
        end

        it 'passes valid_lifetime to the DHCPv4 server resource' do
          is_expected.to contain_kea_dhcp_v4_server('dhcp4').with(
            'valid_lifetime' => 86_000,
          )
        end
      end

      context 'with renew_timer and rebind_timer set' do
        let(:params) do
          super().merge(renew_timer: 43_000, rebind_timer: 3600)
        end

        it 'passes renew_timer and rebind_timer to the DHCPv4 server resource' do
          is_expected.to contain_kea_dhcp_v4_server('dhcp4').with(
            'renew_timer' => 43_000,
            'rebind_timer' => 3600,
          )
        end
      end

      context 'with explicit listen interfaces' do
        let(:params) do
          super().merge(array_dhcp4_listen_interfaces: ['enp5s0', 'enp6s0'])
        end

        it 'passes interfaces to the DHCPv4 server resource' do
          is_expected.to contain_kea_dhcp_v4_server('dhcp4').with(
            'interfaces_config' => { 'interfaces' => ['enp5s0', 'enp6s0'] },
          )
        end
      end

      context 'with dhcp4_socket_type set' do
        let(:params) do
          super().merge(dhcp4_socket_type: 'udp')
        end

        it 'includes dhcp-socket-type in interfaces_config' do
          is_expected.to contain_kea_dhcp_v4_server('dhcp4').with(
            'interfaces_config' => { 'interfaces' => ['*'], 'dhcp-socket-type' => 'udp' },
          )
        end
      end

      context 'with DDNS enabled' do
        it 'manages the DDNS server configuration' do
          is_expected.to contain_kea_ddns_server('dhcp-ddns').with(
            'ensure' => 'present',
            'ip_address' => '127.0.0.1',
            'port' => 53_001,
            'dns_server_timeout' => 500,
            'ncr_protocol' => 'UDP',
            'ncr_format' => 'JSON',
            'tsig_keys' => [],
          )
        end
      end

      context 'with DDNS disabled' do
        let(:params) do
          super().merge(enable_ddns: false)
        end

        it 'does not manage the DDNS server configuration' do
          is_expected.not_to contain_kea_ddns_server('dhcp-ddns')
        end
      end

      context 'with custom DDNS parameters' do
        let(:params) do
          super().merge(
            ddns_ip_address: '192.168.1.10',
            ddns_port: 8053,
            ddns_server_timeout: 1000,
            ddns_ncr_protocol: 'TCP',
            ddns_tsig_keys: [
              {
                'name' => 'test-key',
                'algorithm' => 'HMAC-SHA256',
                'secret' => 'abc123==',
              },
            ],
          )
        end

        it 'manages DDNS server with custom parameters' do
          is_expected.to contain_kea_ddns_server('dhcp-ddns').with(
            'ip_address' => '192.168.1.10',
            'port' => 8053,
            'dns_server_timeout' => 1000,
            'ncr_protocol' => 'TCP',
            'tsig_keys' => [
              {
                'name' => 'test-key',
                'algorithm' => 'HMAC-SHA256',
                'secret' => 'abc123==',
              },
            ],
          )
        end
      end

      context 'with secret_file_content TSIG keys' do
        let(:params) do
          super().merge(
            enable_ddns: true,
            ddns_tsig_keys: [
              {
                'name'                => 'ddns-key',
                'algorithm'           => 'HMAC-SHA256',
                'secret_file_content' => 'LSWXnfkKZjdPJI5QxlpnfQ==',
              },
            ],
          )
        end

        it { is_expected.to compile.with_all_deps }

        it 'creates the tsig directory before kea_ddns_server' do
          is_expected.to contain_file('/etc/kea/tsig').with(
            'ensure' => 'directory',
            'owner'  => 'root',
            'group'  => 'kea',
            'mode'   => '0750',
          ).that_comes_before('Kea_ddns_server[dhcp-ddns]')
        end

        it 'creates the key file with restricted permissions before kea_ddns_server' do
          is_expected.to contain_file('/etc/kea/tsig/ddns-key.tsig').with(
            'ensure'    => 'file',
            'owner'     => 'root',
            'group'     => 'kea',
            'mode'      => '0640',
            'show_diff' => false,
          ).that_comes_before('Kea_ddns_server[dhcp-ddns]')
        end

        it 'passes secret-file path to kea_ddns_server' do
          is_expected.to contain_kea_ddns_server('dhcp-ddns').with(
            'tsig_keys' => [
              {
                'name'        => 'ddns-key',
                'algorithm'   => 'HMAC-SHA256',
                'secret-file' => '/etc/kea/tsig/ddns-key.tsig',
              },
            ],
          )
        end
      end

      context 'with mixed secret and secret_file_content TSIG keys' do
        let(:params) do
          super().merge(
            enable_ddns: true,
            ddns_tsig_keys: [
              {
                'name'      => 'plain-key',
                'algorithm' => 'HMAC-SHA256',
                'secret'    => 'abc123==',
              },
              {
                'name'                => 'file-key',
                'algorithm'           => 'HMAC-SHA256',
                'secret_file_content' => 'LSWXnfkKZjdPJI5QxlpnfQ==',
              },
            ],
          )
        end

        it { is_expected.to compile.with_all_deps }

        it 'creates file for the secret_file_content key' do
          is_expected.to contain_file('/etc/kea/tsig/file-key.tsig').with(
            'ensure' => 'file',
            'owner'  => 'root',
            'group'  => 'kea',
            'mode'   => '0640',
          )
        end

        it 'passes both keys correctly to kea_ddns_server' do
          is_expected.to contain_kea_ddns_server('dhcp-ddns').with(
            'tsig_keys' => [
              {
                'name'      => 'plain-key',
                'algorithm' => 'HMAC-SHA256',
                'secret'    => 'abc123==',
              },
              {
                'name'        => 'file-key',
                'algorithm'   => 'HMAC-SHA256',
                'secret-file' => '/etc/kea/tsig/file-key.tsig',
              },
            ],
          )
        end
      end

      context 'with PostgreSQL setup (instance mode, default)' do
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

      context 'with database install mode' do
        let(:params) do
          super().merge(lease_backend_install_mode: 'database')
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_postgresql__server_instance('kea') }

        it 'creates the application database without a dedicated instance' do
          is_expected.to contain_postgresql__server__db('kea').with(
            'user' => 'kea',
            'port' => 5433,
          )
          is_expected.not_to contain_postgresql__server__db('kea').with(
            'instance' => 'kea',
          )
        end

        it 'initializes the schema' do
          is_expected.to contain_exec('init_kea_dhcp_schema').with(
            'command' => "/usr/sbin/kea-admin db-init pgsql -u kea -p \"\${PGPASSWORD}\" -h 127.0.0.1 -P 5433 -n kea",
            'user' => 'postgres',
          ).that_requires('Postgresql::Server::Db[kea]')
        end
      end

      context 'with none install mode' do
        let(:params) do
          super().merge(lease_backend_install_mode: 'none')
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('kea_dhcp::install::postgresql') }
        it { is_expected.not_to contain_postgresql__server_instance('kea') }
        it { is_expected.not_to contain_exec('init_kea_dhcp_schema') }
      end

      context 'with host_backend postgresql' do
        let(:params) do
          super().merge(
            host_backend: 'postgresql',
            host_sensitive_db_password: RSpec::Puppet::RawString.new("Sensitive('host_password')"),
            host_database_name: 'kea_hosts',
            host_database_user: 'kea_hosts',
            host_database_host: '127.0.0.1',
            host_database_port: 5432,
          )
        end

        it { is_expected.to compile.with_all_deps }

        it 'includes libdhcp_host_cmds.so in hooks_libraries' do
          hooks = catalogue.resource('Kea_dhcp_v4_server', 'dhcp4')[:hooks_libraries]
          expect(hooks).to include({ 'library' => '/usr/lib64/kea/hooks/libdhcp_host_cmds.so' })
        end

        it 'passes host_database to the DHCPv4 server resource' do
          host_database = catalogue.resource('Kea_dhcp_v4_server', 'dhcp4')[:host_database]
          expect(host_database).to include(
            'type' => 'postgresql',
            'name' => 'kea_hosts',
            'user' => 'kea_hosts',
            'host' => '127.0.0.1',
            'port' => 5432,
          )
          expect(host_database['password']).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
          expect(host_database['password'].unwrap).to eq('host_password')
        end
      end

      context 'with host_backend json (default)' do
        it 'does not include libdhcp_host_cmds.so in hooks_libraries' do
          hooks = catalogue.resource('Kea_dhcp_v4_server', 'dhcp4')[:hooks_libraries]
          host_cmds_lib = '/usr/lib64/kea/hooks/libdhcp_host_cmds.so'
          expect(Array(hooks).map { |h| h['library'] }).not_to include(host_cmds_lib)
        end

        it 'does not pass host_database to the DHCPv4 server resource' do
          host_database = catalogue.resource('Kea_dhcp_v4_server', 'dhcp4')[:host_database]
          expect(host_database).to be_nil.or(be_empty)
        end
      end
    end
  end
end
