# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp class on Rocky' do
  before(:all) do
    reset_kea_configs
    install_repository
  end

  describe 'instance mode installation' do
    let(:db_password) { 'LitmusP@ssw0rd!' }
    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password       => Sensitive('#{db_password}'),
          array_dhcp4_server_options  => [
            { 'name' => 'routers', 'data' => '192.0.2.1' },
          ],
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
          lease_backend_install_mode  => 'instance',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    describe package('isc-kea') do
      it { is_expected.to be_installed }

      it 'installs kea 3.0.x' do
        version = run_shell("rpm -q --qf '%{VERSION}' isc-kea").stdout.strip
        expect(version).to match(%r{\A3\.0\.})
      end
    end

    it 'creates the PostgreSQL database for leases' do
      query = "SELECT 1 FROM pg_database WHERE datname = 'kea';"
      result = run_shell("su - postgres -c \"psql -p 5433 -tAc \\\"#{query}\\\"\"")
      expect(result.stdout).to match(%r{1})
    end

    it 'starts the required services' do
      ['kea-dhcp4', 'postgresql@kea'].each do |svc|
        status = run_shell("systemctl is-active #{svc}", expect_failures: false)
        expect(status.stdout.strip).to eq('active')
      end
    end

    it 'creates the kea-dhcp4 configuration with the expected lease database' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      dhcp4 = config.fetch('Dhcp4')
      lease_db = dhcp4.fetch('lease-database')

      expect(lease_db['name']).to eq('kea')
      expect(lease_db['user']).to eq('kea')
      expect(lease_db['port']).to eq(5433)

      server_options = Array(dhcp4['option-data'])
      router_option = server_options.find { |opt| opt['name'] == 'routers' }
      expect(router_option).not_to be_nil
      expect(router_option['data']).to eq('192.0.2.1')
    end
  end

  describe 'interface configuration' do
    before(:all) do
      reset_kea_configs
    end

    after(:all) do
      reset_kea_configs
    end

    context 'with default interface configuration' do
      let(:manifest) do
        <<~PP
          class { 'kea_dhcp':
            lease_sensitive_db_password      => Sensitive('LitmusP@ssw0rd!'),
            enable_ddns                => false,
            enable_ctrl_agent          => false,
          }
        PP
      end

      it 'applies the manifest idempotently' do
        apply_manifest(manifest, catch_failures: true)
        apply_manifest(manifest, catch_changes: true)
      end

      it 'writes interfaces-config listening on all interfaces' do
        config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
        interfaces_config = config.dig('Dhcp4', 'interfaces-config')

        expect(interfaces_config).not_to be_nil
        expect(interfaces_config['interfaces']).to eq(['*'])
        expect(interfaces_config).not_to have_key('dhcp-socket-type')
      end
    end

    context 'with explicit interface list' do
      let(:manifest) do
        <<~PP
          class { 'kea_dhcp':
            lease_sensitive_db_password         => Sensitive('LitmusP@ssw0rd!'),
            enable_ddns                   => false,
            enable_ctrl_agent             => false,
            array_dhcp4_listen_interfaces => ['lo'],
          }
        PP
      end

      it 'applies the manifest idempotently' do
        apply_manifest(manifest, catch_failures: true)
        apply_manifest(manifest, catch_changes: true)
      end

      it 'writes the specified interfaces to the config' do
        config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
        interfaces_config = config.dig('Dhcp4', 'interfaces-config')

        expect(interfaces_config['interfaces']).to eq(['lo'])
      end
    end

    context 'with dhcp-socket-type set to udp' do
      let(:manifest) do
        <<~PP
          class { 'kea_dhcp':
            lease_sensitive_db_password      => Sensitive('LitmusP@ssw0rd!'),
            enable_ddns                => false,
            enable_ctrl_agent          => false,
            dhcp4_socket_type          => 'udp',
          }
        PP
      end

      it 'applies the manifest idempotently' do
        apply_manifest(manifest, catch_failures: true)
        apply_manifest(manifest, catch_changes: true)
      end

      it 'writes dhcp-socket-type to the interfaces-config' do
        config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
        interfaces_config = config.dig('Dhcp4', 'interfaces-config')

        expect(interfaces_config['interfaces']).to eq(['*'])
        expect(interfaces_config['dhcp-socket-type']).to eq('udp')
      end
    end
  end

  describe 'DDNS integration' do
    let(:db_password) { 'LitmusP@ssw0rd!' }
    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password       => Sensitive('#{db_password}'),
          array_dhcp4_server_options  => [
            { 'name' => 'routers', 'data' => '192.0.2.1' },
          ],
          enable_ddns                 => true,
          enable_ctrl_agent           => false,
          dhcp_ddns                   => {
            'enable-updates'                => true,
            'server-ip'                     => '127.0.0.1',
            'server-port'                   => 53001,
            'sender-ip'                     => '',
            'sender-port'                   => 0,
            'max-queue-size'                => 1024,
            'ncr-protocol'                  => 'UDP',
            'ncr-format'                    => 'JSON',
          },
          ddns_tsig_keys              => [
            {
              'name'      => 'ddns-key',
              'algorithm' => 'HMAC-SHA256',
              'secret'    => 'LSWXnfkKZjdPJI5QxlpnfQ==',
            },
          ],
        }

        kea_ddns_domain { 'forward-zone':
          ensure      => present,
          domain_name => 'example.com.',
          direction   => 'forward',
          key_name    => 'ddns-key',
          dns_servers => [
            {
              'ip-address' => '192.0.2.53',
              'port'       => 53,
            },
          ],
        }

        kea_ddns_domain { 'reverse-zone':
          ensure      => present,
          domain_name => '2.0.192.in-addr.arpa.',
          direction   => 'reverse',
          dns_servers => [
            {
              'ip-address' => '192.0.2.53',
              'port'       => 53,
            },
          ],
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'configures DDNS settings in kea-dhcp4.conf' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      dhcp4 = config.fetch('Dhcp4')
      dhcp_ddns = dhcp4.fetch('dhcp-ddns')

      expect(dhcp_ddns['enable-updates']).to be true
      expect(dhcp_ddns['server-ip']).to eq('127.0.0.1')
      expect(dhcp_ddns['server-port']).to eq(53_001)
      expect(dhcp_ddns['sender-ip']).to eq('')
      expect(dhcp_ddns['sender-port']).to eq(0)
      expect(dhcp_ddns['max-queue-size']).to eq(1024)
      expect(dhcp_ddns['ncr-protocol']).to eq('UDP')
      expect(dhcp_ddns['ncr-format']).to eq('JSON')
    end

    it 'configures DDNS server in kea-dhcp-ddns.conf' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp-ddns.conf').stdout)
      ddns = config.fetch('DhcpDdns')

      expect(ddns['ip-address']).to eq('127.0.0.1')
      expect(ddns['port']).to eq(53_001)
      expect(ddns['dns-server-timeout']).to eq(500)

      tsig_keys = ddns.fetch('tsig-keys')
      expect(tsig_keys.length).to eq(1)
      expect(tsig_keys[0]['name']).to eq('ddns-key')
      expect(tsig_keys[0]['algorithm']).to eq('HMAC-SHA256')
    end

    it 'configures forward and reverse DDNS domains' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp-ddns.conf').stdout)
      ddns = config.fetch('DhcpDdns')

      forward_domains = ddns.fetch('forward-ddns').fetch('ddns-domains')
      expect(forward_domains.length).to eq(1)
      expect(forward_domains[0]['name']).to eq('example.com.')
      expect(forward_domains[0]['key-name']).to eq('ddns-key')

      reverse_domains = ddns.fetch('reverse-ddns').fetch('ddns-domains')
      expect(reverse_domains.length).to eq(1)
      expect(reverse_domains[0]['name']).to eq('2.0.192.in-addr.arpa.')
    end

    it 'starts the kea-dhcp-ddns service when enabled' do
      status = run_shell('systemctl is-active kea-dhcp-ddns', expect_failures: false)
      expect(status.stdout.strip).to eq('active')
    end
  end

  describe 'invalid server options' do
    before(:all) do
      reset_kea_configs
    end

    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password      => Sensitive('LitmusP@ssw0rd!'),
          array_dhcp4_server_options => [
            { 'name' => 'time-servers', 'data' => 'not-an-ip-address' },
          ],
          enable_ddns                => false,
          enable_ctrl_agent          => false,
        }
      PP
    end

    it 'prints kea errors when validation fails' do
      result = apply_manifest(manifest, catch_failures: false)
      expect(result.stderr).to match(%r{Kea_dhcp_v4_commit\[/etc/kea/kea-dhcp4\.conf\]})
      expect(result.stderr).to match(%r{ERROR \[kea-dhcp4})
    end
  end

  describe 'database mode installation' do
    before(:all) do
      reset_kea_configs
    end

    let(:db_password) { 'LitmusP@ssw0rd!' }
    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password      => Sensitive('#{db_password}'),
          array_dhcp4_server_options => [
            { 'name' => 'routers', 'data' => '192.0.2.1' },
          ],
          enable_ddns                => false,
          enable_ctrl_agent          => false,
          lease_database_port        => 5432,
          lease_backend_install_mode => 'database',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates the kea database in the default PostgreSQL instance' do
      query = "SELECT 1 FROM pg_database WHERE datname = 'kea';"
      result = run_shell("su - postgres -c \"psql -p 5432 -tAc \\\"#{query}\\\"\"")
      expect(result.stdout).to match(%r{1})
    end

    it 'initializes the Kea schema in the default PostgreSQL instance' do
      result = run_shell('su - postgres -c "psql -p 5432 -d kea -tAc \"SELECT 1 FROM schema_version;\""')
      expect(result.stdout).to match(%r{1})
    end

    it 'starts the kea-dhcp4 service' do
      status = run_shell('systemctl is-active kea-dhcp4', expect_failures: false)
      expect(status.stdout.strip).to eq('active')
    end

    it 'creates the kea-dhcp4 configuration pointing to the default instance' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      dhcp4 = config.fetch('Dhcp4')
      lease_db = dhcp4.fetch('lease-database')

      expect(lease_db['name']).to eq('kea')
      expect(lease_db['user']).to eq('kea')
      expect(lease_db['port']).to eq(5432)

      server_options = Array(dhcp4['option-data'])
      router_option = server_options.find { |opt| opt['name'] == 'routers' }
      expect(router_option).not_to be_nil
      expect(router_option['data']).to eq('192.0.2.1')
    end
  end

  describe 'DDNS with secret-file TSIG key' do
    before(:all) do
      reset_kea_configs
    end

    let(:secret_value) { 'LSWXnfkKZjdPJI5QxlpnfQ==' }
    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          enable_ddns                 => true,
          enable_ctrl_agent           => false,
          ddns_tsig_keys              => [
            {
              'name'                => 'ddns-key',
              'algorithm'           => 'HMAC-SHA256',
              'secret_file_content' => Sensitive('#{secret_value}'),
            },
          ],
        }
      PP
    end

    it 'applies without failures' do
      apply_manifest(manifest, catch_failures: true)
    end

    it 'applies idempotently' do
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates the TSIG key file with restricted permissions' do
      result = run_shell('stat -c "%a %U %G" /etc/kea/tsig/ddns-key.tsig')
      expect(result.stdout.strip).to eq('640 root kea')
    end

    it 'configures kea-dhcp-ddns.conf with secret-file (not secret)' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp-ddns.conf').stdout)
      tsig_keys = config.dig('DhcpDdns', 'tsig-keys')

      expect(tsig_keys).not_to be_nil
      expect(tsig_keys.length).to eq(1)
      expect(tsig_keys[0]['name']).to eq('ddns-key')
      expect(tsig_keys[0]).to have_key('secret-file')
      expect(tsig_keys[0]).not_to have_key('secret')
      expect(tsig_keys[0]['secret-file']).to eq('/etc/kea/tsig/ddns-key.tsig')
    end

    it 'does not expose TSIG secrets in provider debug messages' do
      # Puppet itself may log property values in debug output. This test checks
      # that the provider's own debug messages (kea_ddns_server and kea-dhcp-ddns
      # commit lines) do not contain the raw secret.
      run_shell(<<~BASH)
        cat > /tmp/kea_tsig_debug_test.pp << 'PPEOF'
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          enable_ddns                 => true,
          enable_ctrl_agent           => false,
          ddns_tsig_keys              => [
            {
              'name'      => 'ddns-key',
              'algorithm' => 'HMAC-SHA256',
              'secret'    => 'LSWXnfkKZjdPJI5QxlpnfQ==',
            },
          ],
        }
        PPEOF
      BASH

      result = run_shell('puppet apply --debug /tmp/kea_tsig_debug_test.pp 2>&1 || true')

      # Filter to provider-specific debug lines
      provider_lines = result.stdout.lines.select do |line|
        line.include?('kea_ddns_server') || line.include?('kea-dhcp-ddns committing')
      end
      expect(provider_lines.join).not_to include('LSWXnfkKZjdPJI5QxlpnfQ==')
    ensure
      run_shell('rm -f /tmp/kea_tsig_debug_test.pp', expect_failures: true)
    end
  end

  describe 'host database configuration' do
    before(:all) do
      reset_kea_configs
    end

    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          host_backend                => 'postgresql',
          host_sensitive_db_password  => Sensitive('LitmusP@ssw0rd!'),
          host_database_port          => 5433,
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'writes hosts-database to kea-dhcp4.conf' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      host_db = config.dig('Dhcp4', 'hosts-database')

      expect(host_db).not_to be_nil
      expect(host_db['type']).to eq('postgresql')
      expect(host_db['name']).to eq('kea')
      expect(host_db['port']).to eq(5433)
    end

    it 'loads libdhcp_host_cmds.so in hooks-libraries' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      libraries = Array(config.dig('Dhcp4', 'hooks-libraries')).map { |h| h['library'] }

      expect(libraries).to include('/usr/lib64/kea/hooks/libdhcp_host_cmds.so')
    end
  end

  describe 'DDNS behavioral parameters' do
    before(:all) do
      reset_kea_configs
    end

    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
          ddns_qualifying_suffix      => 'example.org',
          ddns_update_on_renew        => true,
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'writes ddns-qualifying-suffix to kea-dhcp4.conf' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      expect(config.dig('Dhcp4', 'ddns-qualifying-suffix')).to eq('example.org')
    end

    it 'writes ddns-update-on-renew to kea-dhcp4.conf' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      expect(config.dig('Dhcp4', 'ddns-update-on-renew')).to be(true)
    end
  end

  describe 'DDNS behavioral parameters at scope level' do
    before(:all) do
      reset_kea_configs
      base_manifest = <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
        }
      PP
      apply_manifest(base_manifest, catch_failures: true)
    end

    let(:manifest) do
      <<~PP
        kea_dhcp_v4_scope { 'ddns-test-scope':
          ensure                  => present,
          subnet                  => '192.0.2.0/24',
          pools                   => ['192.0.2.10 - 192.0.2.200'],
          ddns_qualifying_suffix  => 'example.org',
          ddns_update_on_renew    => true,
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'writes ddns-qualifying-suffix to the scope entry' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      scope = Array(config.dig('Dhcp4', 'subnet4')).find { |s| s.dig('user-context', 'puppet_name') == 'ddns-test-scope' }

      expect(scope).not_to be_nil
      expect(scope['ddns-qualifying-suffix']).to eq('example.org')
    end

    it 'writes ddns-update-on-renew to the scope entry' do
      config = JSON.parse(run_shell('cat /etc/kea/kea-dhcp4.conf').stdout)
      scope = Array(config.dig('Dhcp4', 'subnet4')).find { |s| s.dig('user-context', 'puppet_name') == 'ddns-test-scope' }

      expect(scope).not_to be_nil
      expect(scope['ddns-update-on-renew']).to be(true)
    end
  end
end
