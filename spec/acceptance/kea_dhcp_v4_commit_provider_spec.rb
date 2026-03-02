# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp_v4_commit provider' do
  let(:config_path) { '/etc/kea/kea-dhcp4.conf' }

  before :all do
    reset_kea_configs
    install_repository
    base_manifest = <<~PP
      class { 'kea_dhcp':
        lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
        enable_ddns           => false,
        enable_ctrl_agent     => false,
      }
    PP
    apply_manifest(base_manifest, catch_failures: true)
  end

  context 'when a scope is applied' do
    before(:each) do
      run_shell("rm -f #{config_path}")
    end

    it 'auto-creates the commit resource which appears as changed on the first run but not the second' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'commit-scope':
          ensure      => present,
          subnet      => '192.0.2.0/24',
          pools       => ['192.0.2.10 - 192.0.2.200'],
          config_path => '#{config_path}',
        }
      PP

      first_result = apply_manifest(manifest, catch_failures: true)
      expect(first_result.stdout).to match(%r{Kea_dhcp_v4_commit\[#{Regexp.escape(config_path)}\]})

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      scope = config['Dhcp4']['subnet4'].find { |s| s.dig('user-context', 'puppet_name') == 'commit-scope' }
      expect(scope).not_to be_nil
      expect(scope['subnet']).to eq('192.0.2.0/24')

      # Second run: scope is already correct, dirty_paths is empty, commit resource is in sync
      apply_manifest(manifest, catch_changes: true)
    end
  end

  context 'when server and scope are both in the catalog' do
    before(:each) do
      run_shell("rm -f #{config_path}")
    end

    it 'commits a single time via the commit resource, not via post_resource_eval' do
      manifest = <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          enable_ddns           => false,
          enable_ctrl_agent     => false,
        }

        kea_dhcp_v4_scope { 'server-and-scope':
          ensure => present,
          subnet => '192.0.2.0/24',
          pools  => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      result = apply_manifest(manifest, catch_failures: true)

      expect(result.stdout).to match(%r{Kea_dhcp_v4_commit\[#{Regexp.escape(config_path)}\]})
      expect(result.stdout).not_to match(%r{post_resource_eval})

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnets = config['Dhcp4']['subnet4']
      scope = subnets.find { |s| s.dig('user-context', 'puppet_name') == 'server-and-scope' }
      expect(scope).not_to be_nil
    end
  end

  context 'when verifying temp directory cleanup' do
    before(:each) do
      run_shell("rm -f #{config_path}")
      run_shell("find /tmp -maxdepth 1 -name 'kea-dhcp4*' -type d -exec rm -rf {} + 2>/dev/null; true")
    end

    it 'leaves no temp directories after a successful commit' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'cleanup-test':
          ensure      => present,
          subnet      => '10.1.0.0/24',
          pools       => ['10.1.0.10 - 10.1.0.200'],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)

      temp_count = run_shell("find /tmp -maxdepth 1 -name 'kea-dhcp4*' -type d 2>/dev/null | wc -l").stdout.strip.to_i
      expect(temp_count).to eq(0)
    end

    it 'leaves no temp directories after a failed validation' do
      # Seed a valid initial config so there is something to commit on top of
      seed_manifest = <<~PP
        kea_dhcp_v4_scope { 'initial-scope':
          ensure      => present,
          subnet      => '10.1.0.0/24',
          pools       => ['10.1.0.10 - 10.1.0.200'],
          config_path => '#{config_path}',
        }
      PP
      apply_manifest(seed_manifest, catch_failures: true)
      run_shell("find /tmp -maxdepth 1 -name 'kea-dhcp4*' -type d -exec rm -rf {} + 2>/dev/null; true")

      # Pools outside the declared subnet trigger kea-dhcp4 validation failure
      invalid_manifest = <<~PP
        kea_dhcp_v4_scope { 'invalid-scope':
          ensure      => present,
          subnet      => '192.0.2.0/24',
          pools       => ['198.51.100.10 - 198.51.100.200'],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(invalid_manifest, catch_failures: false)

      temp_count = run_shell("find /tmp -maxdepth 1 -name 'kea-dhcp4*' -type d 2>/dev/null | wc -l").stdout.strip.to_i
      expect(temp_count).to eq(0)
    end
  end

  context 'when the generated configuration is invalid' do
    let(:valid_config) do
      <<~JSON
        {
          "Dhcp4": {
            "valid-lifetime": 3600,
            "subnet4": [
              {
                "id": 1,
                "subnet": "10.0.0.0/24",
                "pools": [{"pool": "10.0.0.10 - 10.0.0.100"}]
              }
            ]
          }
        }
      JSON
    end

    before(:each) do
      run_shell("cat <<'JSON' > #{config_path}\n#{valid_config}\nJSON")
    end

    it 'attributes the error to Kea_dhcp_v4_commit and preserves the original config' do
      checksum_before = run_shell("md5sum #{config_path}").stdout.split.first

      manifest = <<~PP
        kea_dhcp_v4_scope { 'invalid-scope':
          subnet      => '192.0.2.0/24',
          pools       => ['198.51.100.10 - 198.51.100.200'],
          config_path => '#{config_path}',
        }
      PP

      result = apply_manifest(manifest, catch_failures: false)

      expect(result.stderr).to match(%r{Kea_dhcp_v4_commit\[#{Regexp.escape(config_path)}\]})
      expect(result.stderr).to match(%r{ERROR \[kea-dhcp4})
      expect(result.stderr).not_to match(%r{post_resource_eval})

      checksum_after = run_shell("md5sum #{config_path}").stdout.split.first
      expect(checksum_after).to eq(checksum_before)
    end
  end
end
