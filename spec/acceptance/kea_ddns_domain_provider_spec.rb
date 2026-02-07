# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_ddns_domain provider' do
  let(:config_path) { '/etc/kea/kea-dhcp-ddns.conf' }

  before :all do
    install_repository
    # Install kea_dhcp to get kea-dhcp-ddns command
    base_manifest = <<~PP
      class { 'kea_dhcp':
        sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
        enable_ddns           => true,
        enable_ctrl_agent     => false,
      }
    PP
    apply_manifest(base_manifest, catch_failures: true)
  end

  context 'when creating forward DDNS domain' do
    before(:each) do
      # Ensure the DDNS server is configured first
      server_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(server_manifest, catch_failures: true)
    end

    let(:manifest) do
      <<~PP
        kea_ddns_domain { 'example-forward':
          ensure      => present,
          domain_name => 'example.com.',
          direction   => 'forward',
          dns_servers => [
            {
              'ip-address' => '192.168.1.10',
              'port'       => 53,
            },
            {
              'ip-address' => '192.168.1.11',
              'port'       => 53,
            },
          ],
          config_path => '#{config_path}',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates the forward domain in the configuration' do
      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      forward_ddns = config.fetch('DhcpDdns').fetch('forward-ddns')
      domains = forward_ddns.fetch('ddns-domains')

      expect(domains.length).to eq(1)
      domain = domains[0]

      expect(domain['name']).to eq('example.com.')
      expect(domain.dig('user-context', 'puppet_name')).to eq('example-forward')

      dns_servers = domain['dns-servers']
      expect(dns_servers.length).to eq(2)
      expect(dns_servers.map { |s| s['ip-address'] }).to include('192.168.1.10', '192.168.1.11')
    end
  end

  context 'when creating reverse DDNS domain' do
    before(:each) do
      # Ensure the DDNS server is configured first
      server_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(server_manifest, catch_failures: true)
    end

    let(:manifest) do
      <<~PP
        kea_ddns_domain { 'example-reverse':
          ensure      => present,
          domain_name => '1.168.192.in-addr.arpa.',
          direction   => 'reverse',
          dns_servers => [
            {
              'ip-address' => '192.168.1.10',
              'port'       => 53,
            },
          ],
          config_path => '#{config_path}',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates the reverse domain in the configuration' do
      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      reverse_ddns = config.fetch('DhcpDdns').fetch('reverse-ddns')
      domains = reverse_ddns.fetch('ddns-domains')

      expect(domains.length).to eq(1)
      domain = domains[0]

      expect(domain['name']).to eq('1.168.192.in-addr.arpa.')
      expect(domain.dig('user-context', 'puppet_name')).to eq('example-reverse')
    end
  end

  context 'when managing domain with TSIG key' do
    let(:manifest) do
      <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          tsig_keys   => [
            {
              name      => 'secure-key',
              algorithm => 'HMAC-SHA256',
              secret    => 'LSWXnfkKZjdPJI5QxlpnfQ==',
            },
          ],
          config_path => '#{config_path}',
        }

        kea_ddns_domain { 'secure-domain':
          ensure      => present,
          domain_name => 'secure.example.com.',
          direction   => 'forward',
          key_name    => 'secure-key',
          dns_servers => [
            {
              'ip-address' => '192.168.1.20',
              'port'       => 53,
            },
          ],
          config_path => '#{config_path}',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates domain with TSIG key reference' do
      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      forward_ddns = config.fetch('DhcpDdns').fetch('forward-ddns')
      domains = forward_ddns.fetch('ddns-domains')

      secure_domain = domains.find { |d| d.dig('user-context', 'puppet_name') == 'secure-domain' }
      expect(secure_domain).not_to be_nil
      expect(secure_domain['key-name']).to eq('secure-key')
    end
  end

  context 'when managing multiple domains' do
    before(:each) do
      # Ensure the DDNS server is configured first
      server_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(server_manifest, catch_failures: true)
    end

    let(:manifest) do
      <<~PP
        kea_ddns_domain { 'domain-a':
          ensure      => present,
          domain_name => 'a.example.com.',
          direction   => 'forward',
          dns_servers => [
            { 'ip-address' => '192.168.1.10' },
          ],
          config_path => '#{config_path}',
        }

        kea_ddns_domain { 'domain-b':
          ensure      => present,
          domain_name => 'b.example.com.',
          direction   => 'forward',
          dns_servers => [
            { 'ip-address' => '192.168.1.11' },
          ],
          config_path => '#{config_path}',
        }

        kea_ddns_domain { 'reverse-1':
          ensure      => present,
          domain_name => '10.168.192.in-addr.arpa.',
          direction   => 'reverse',
          dns_servers => [
            { 'ip-address' => '192.168.1.10' },
          ],
          config_path => '#{config_path}',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates all domains in their respective sections' do
      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      ddns = config.fetch('DhcpDdns')

      forward_domains = ddns.fetch('forward-ddns').fetch('ddns-domains')
      reverse_domains = ddns.fetch('reverse-ddns').fetch('ddns-domains')

      # Check we have the right number of domains
      forward_count = forward_domains.count { |d| d.dig('user-context', 'puppet_name')&.start_with?('domain-') }
      reverse_count = reverse_domains.count { |d| d.dig('user-context', 'puppet_name')&.start_with?('reverse-') }

      expect(forward_count).to eq(2)
      expect(reverse_count).to eq(1)

      # Verify domain names
      forward_names = forward_domains.map { |d| d['name'] }
      expect(forward_names).to include('a.example.com.', 'b.example.com.')
    end
  end

  context 'when updating domain configuration' do
    before(:each) do
      initial_manifest = <<~PP
        kea_ddns_domain { 'update-test':
          ensure      => present,
          domain_name => 'old.example.com.',
          direction   => 'forward',
          dns_servers => [
            { 'ip-address' => '192.168.1.10', 'port' => 53 },
          ],
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(initial_manifest, catch_failures: true)
    end

    it 'updates domain name and DNS servers' do
      update_manifest = <<~PP
        kea_ddns_domain { 'update-test':
          ensure      => present,
          domain_name => 'new.example.com.',
          direction   => 'forward',
          dns_servers => [
            { 'ip-address' => '192.168.1.20', 'port' => 5353 },
            { 'ip-address' => '192.168.1.21', 'port' => 5353 },
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(update_manifest, catch_failures: true)
      apply_manifest(update_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      forward_ddns = config.fetch('DhcpDdns').fetch('forward-ddns')
      domains = forward_ddns.fetch('ddns-domains')

      domain = domains.find { |d| d.dig('user-context', 'puppet_name') == 'update-test' }
      expect(domain).not_to be_nil
      expect(domain['name']).to eq('new.example.com.')
      expect(domain['dns-servers'].length).to eq(2)
      expect(domain['dns-servers'].all? { |s| s['port'] == 5353 }).to be true
    end
  end

  context 'when removing domain' do
    before(:each) do
      manifest = <<~PP
        kea_ddns_domain { 'to-remove':
          ensure      => present,
          domain_name => 'remove.example.com.',
          direction   => 'forward',
          dns_servers => [
            { 'ip-address' => '192.168.1.10' },
          ],
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(manifest, catch_failures: true)
    end

    it 'removes the domain from configuration' do
      destroy_manifest = <<~PP
        kea_ddns_domain { 'to-remove':
          ensure      => absent,
          domain_name => 'remove.example.com.',
          direction   => 'forward',
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(destroy_manifest, catch_failures: true)
      apply_manifest(destroy_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      forward_ddns = config.fetch('DhcpDdns').fetch('forward-ddns')
      domains = forward_ddns.fetch('ddns-domains')

      removed_domain = domains.find { |d| d.dig('user-context', 'puppet_name') == 'to-remove' }
      expect(removed_domain).to be_nil
    end
  end

  context 'when preserving unmanaged domains' do
    let(:preseed_config) do
      <<~JSON
        {
          "DhcpDdns": {
            "ip-address": "127.0.0.1",
            "port": 53001,
            "forward-ddns": {
              "ddns-domains": [
                {
                  "name": "unmanaged.example.com.",
                  "dns-servers": [
                    { "ip-address": "192.168.1.99" }
                  ]
                }
              ]
            },
            "reverse-ddns": {}
          }
        }
      JSON
    end

    before(:each) do
      run_shell("cat <<'JSON' > #{config_path}\n#{preseed_config}\nJSON")
    end

    it 'preserves unmanaged domains while adding Puppet-managed ones' do
      manifest = <<~PP
        kea_ddns_domain { 'managed-domain':
          ensure      => present,
          domain_name => 'managed.example.com.',
          direction   => 'forward',
          dns_servers => [
            { 'ip-address' => '192.168.1.50' },
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      forward_ddns = config.fetch('DhcpDdns').fetch('forward-ddns')
      domains = forward_ddns.fetch('ddns-domains')

      expect(domains.length).to eq(2)

      unmanaged = domains.find { |d| d['name'] == 'unmanaged.example.com.' }
      managed = domains.find { |d| d.dig('user-context', 'puppet_name') == 'managed-domain' }

      expect(unmanaged).not_to be_nil
      expect(managed).not_to be_nil
    end
  end
end
