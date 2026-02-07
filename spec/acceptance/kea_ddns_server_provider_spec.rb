# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_ddns_server provider' do
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

  context 'when creating basic DDNS server configuration' do
    let(:manifest) do
      <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure             => present,
          ip_address         => '127.0.0.1',
          port               => 53001,
          dns_server_timeout => 500,
          ncr_protocol       => 'UDP',
          ncr_format         => 'JSON',
          config_path        => '#{config_path}',
        }
      PP
    end

    it 'applies the manifest idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    it 'creates the configuration file with correct settings' do
      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      ddns = config.fetch('DhcpDdns')

      expect(ddns['ip-address']).to eq('127.0.0.1')
      expect(ddns['port']).to eq(53_001)
      expect(ddns['dns-server-timeout']).to eq(500)
      expect(ddns['ncr-protocol']).to eq('UDP')
      expect(ddns['ncr-format']).to eq('JSON')
      expect(ddns).to have_key('forward-ddns')
      expect(ddns).to have_key('reverse-ddns')
    end
  end

  context 'when managing TSIG keys' do
    let(:manifest) do
      <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '192.168.1.10',
          port        => 53001,
          tsig_keys   => [
            {
              name      => 'example-key',
              algorithm => 'HMAC-SHA256',
              secret    => 'LSWXnfkKZjdPJI5QxlpnfQ==',
            },
            {
              name      => 'backup-key',
              algorithm => 'HMAC-MD5',
              secret    => 'bZEG7Ow8OgAUPfLWV3aAUQ==',
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

    it 'creates TSIG keys in the configuration' do
      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      tsig_keys = config.fetch('DhcpDdns').fetch('tsig-keys')

      expect(tsig_keys.length).to eq(2)

      example_key = tsig_keys.find { |k| k['name'] == 'example-key' }
      expect(example_key).not_to be_nil
      expect(example_key['algorithm']).to eq('HMAC-SHA256')
      expect(example_key['secret']).to eq('LSWXnfkKZjdPJI5QxlpnfQ==')

      backup_key = tsig_keys.find { |k| k['name'] == 'backup-key' }
      expect(backup_key).not_to be_nil
      expect(backup_key['algorithm']).to eq('HMAC-MD5')
    end
  end

  context 'when updating server configuration' do
    before(:each) do
      initial_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(initial_manifest, catch_failures: true)
    end

    it 'updates the IP address and port' do
      update_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '192.168.1.20',
          port        => 8053,
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(update_manifest, catch_failures: true)
      apply_manifest(update_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      ddns = config.fetch('DhcpDdns')

      expect(ddns['ip-address']).to eq('192.168.1.20')
      expect(ddns['port']).to eq(8053)
    end

    it 'adds TSIG keys to existing configuration' do
      update_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          tsig_keys   => [
            {
              name      => 'new-key',
              algorithm => 'HMAC-SHA512',
              secret    => 'abc123def456==',
            },
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(update_manifest, catch_failures: true)
      apply_manifest(update_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      tsig_keys = config.fetch('DhcpDdns').fetch('tsig-keys')

      expect(tsig_keys.length).to eq(1)
      expect(tsig_keys[0]['name']).to eq('new-key')
      expect(tsig_keys[0]['algorithm']).to eq('HMAC-SHA512')
    end
  end

  context 'when removing server configuration' do
    before(:each) do
      manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          tsig_keys   => [
            {
              name      => 'test-key',
              algorithm => 'HMAC-MD5',
              secret    => 'test123==',
            },
          ],
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(manifest, catch_failures: true)
    end

    it 'removes server properties but preserves structure' do
      destroy_manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => absent,
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(destroy_manifest, catch_failures: true)
      apply_manifest(destroy_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      ddns = config.fetch('DhcpDdns')

      expect(ddns).not_to have_key('ip-address')
      expect(ddns).not_to have_key('port')
      expect(ddns).not_to have_key('tsig-keys')
      expect(ddns).to have_key('forward-ddns')
      expect(ddns).to have_key('reverse-ddns')
    end
  end
end
