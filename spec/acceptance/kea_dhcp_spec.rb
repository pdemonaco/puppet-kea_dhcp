# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp class on Rocky' do
  before(:all) do
    install_repository
  end

  describe 'base installation' do
    let(:db_password) { 'LitmusP@ssw0rd!' }
    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          sensitive_db_password       => Sensitive('#{db_password}'),
          array_dhcp4_server_options  => [
            { 'name' => 'routers', 'data' => '192.0.2.1' },
          ],
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
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

  describe 'DDNS integration' do
    let(:db_password) { 'LitmusP@ssw0rd!' }
    let(:manifest) do
      <<~PP
        class { 'kea_dhcp':
          sensitive_db_password       => Sensitive('#{db_password}'),
          array_dhcp4_server_options  => [
            { 'name' => 'routers', 'data' => '192.0.2.1' },
          ],
          enable_ddns                 => true,
          enable_ctrl_agent           => false,
        }

        kea_dhcp_v4_server { 'dhcp4':
          dhcp_ddns => {
            'enable-updates'                => true,
            'server-ip'                     => '127.0.0.1',
            'server-port'                   => 53001,
            'sender-ip'                     => '',
            'sender-port'                   => 0,
            'max-queue-size'                => 1024,
            'ncr-protocol'                  => 'UDP',
            'ncr-format'                    => 'JSON',
            'ddns-send-updates'             => true,
            'ddns-override-no-update'       => false,
            'ddns-override-client-update'   => false,
            'ddns-replace-client-name'      => 'never',
            'ddns-generated-prefix'         => 'myhost',
            'ddns-qualifying-suffix'        => '',
          },
        }

        kea_ddns_server { 'dhcp-ddns':
          ensure             => present,
          ip_address         => '127.0.0.1',
          port               => 53001,
          dns_server_timeout => 500,
          ncr_protocol       => 'UDP',
          ncr_format         => 'JSON',
          tsig_keys          => [
            {
              name      => 'ddns-key',
              algorithm => 'HMAC-SHA256',
              secret    => 'LSWXnfkKZjdPJI5QxlpnfQ==',
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
      expect(dhcp_ddns['ncr-protocol']).to eq('UDP')
      expect(dhcp_ddns['ncr-format']).to eq('JSON')
      expect(dhcp_ddns['ddns-send-updates']).to be true
      expect(dhcp_ddns['ddns-replace-client-name']).to eq('never')
      expect(dhcp_ddns['ddns-generated-prefix']).to eq('myhost')
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
end
