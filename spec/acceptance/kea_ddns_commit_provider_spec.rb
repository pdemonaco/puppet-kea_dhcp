# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_ddns_commit provider' do
  let(:config_path) { '/etc/kea/kea-dhcp-ddns.conf' }

  before :all do
    reset_kea_configs
    install_repository
    base_manifest = <<~PP
      class { 'kea_dhcp':
        sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
        enable_ddns           => true,
        enable_ctrl_agent     => false,
      }
    PP
    apply_manifest(base_manifest, catch_failures: true)
  end

  context 'when a domain is applied' do
    before(:each) do
      run_shell("rm -f #{config_path}")
    end

    it 'auto-creates the commit resource which appears as changed on the first run but not the second' do
      manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          config_path => '#{config_path}',
        }

        kea_ddns_domain { 'commit-domain':
          ensure      => present,
          domain_name => 'example.com.',
          direction   => 'forward',
          dns_servers => [{ 'ip-address' => '192.168.1.10', 'port' => 53 }],
          config_path => '#{config_path}',
        }
      PP

      first_result = apply_manifest(manifest, catch_failures: true)
      expect(first_result.stdout).to match(%r{Kea_ddns_commit\[#{Regexp.escape(config_path)}\]})

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      domains = config['DhcpDdns']['forward-ddns']['ddns-domains']
      domain = domains.find { |d| d.dig('user-context', 'puppet_name') == 'commit-domain' }
      expect(domain).not_to be_nil
      expect(domain['name']).to eq('example.com.')

      # Second run: already in sync, commit resource is not changed
      apply_manifest(manifest, catch_changes: true)
    end
  end

  context 'when the generated configuration is invalid' do
    let(:invalid_config) do
      <<~JSON
        {
          "DhcpDdns": {
            "ip-address": "127.0.0.1",
            "port": 53001,
            "forward-ddns": { "ddns-domains": [] },
            "reverse-ddns": { "ddns-domains": [] },
            "tsig-keys": [
              {
                "name": "bad-key",
                "algorithm": "NOT-A-VALID-ALGORITHM",
                "secret": "aGVsbG8="
              }
            ]
          }
        }
      JSON
    end

    before(:each) do
      run_shell("cp #{config_path} #{config_path}.commit_test_bak 2>/dev/null || true")
      run_shell("cat <<'JSON' > #{config_path}\n#{invalid_config}\nJSON")
    end

    after(:each) do
      run_shell("mv #{config_path}.commit_test_bak #{config_path} 2>/dev/null || true")
    end

    it 'attributes the error to Kea_ddns_commit and preserves the original config' do
      checksum_before = run_shell("md5sum #{config_path}").stdout.split.first

      manifest = <<~PP
        kea_ddns_server { 'dhcp-ddns':
          ensure      => present,
          ip_address  => '127.0.0.1',
          port        => 53001,
          config_path => '#{config_path}',
        }
      PP

      result = apply_manifest(manifest, catch_failures: false)

      expect(result.stderr).to match(%r{Kea_ddns_commit\[#{Regexp.escape(config_path)}\]})
      expect(result.stderr).to match(%r{ERROR \[kea-dhcp-ddns})

      checksum_after = run_shell("md5sum #{config_path}").stdout.split.first
      expect(checksum_after).to eq(checksum_before)
    end
  end
end
