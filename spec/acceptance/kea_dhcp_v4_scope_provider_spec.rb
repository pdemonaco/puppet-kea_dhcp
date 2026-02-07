# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp_v4_scope provider' do
  let(:config_path) { '/etc/kea/kea-dhcp4.conf' }

  before :all do
    reset_kea_configs
    install_repository
    base_manifest = <<~PP
      class { 'kea_dhcp':
        sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
        enable_ddns           => false,
        enable_ctrl_agent     => false,
      }
    PP
    apply_manifest(base_manifest, catch_failures: true)
  end

  context 'when the configuration already contains unmanaged data' do
    let(:preseed_config) do
      <<~JSON
        {
          "Dhcp4": {
            "valid-lifetime": 7200,
            "control-socket": {
              "socket-type": "unix",
              "socket-name": "/var/run/kea/kea4-ctrl-socket"
            },
            "subnet4": [
              {
                "id": 1,
                "subnet": "192.0.2.0/24",
                "comment": "existing scope",
                "user-context": { "puppet_name": "legacy-scope", "custom_data": "should remain" },
                "pools": [
                  { "pool": "192.0.2.10 - 192.0.2.200" }
                ],
                "option-data": [
                  { "name": "routers", "data": "192.0.2.1" }
                ]
              }
            ],
            "loggers": [
              {
                "name": "kea-dhcp4",
                "output-options": [
                  { "output": "stdout" }
                ],
                "severity": "INFO"
              }
            ]
          }
        }
      JSON
    end

    before(:each) do
      run_shell("cat <<'JSON' > #{config_path}\n#{preseed_config}\nJSON")
    end

    it 'preserves unmanaged keys while adding new scopes' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'new-scope':
          ensure      => present,
          subnet      => '198.51.100.0/24',
          pools       => ['198.51.100.10 - 198.51.100.200'],
          options     => [
            { name => 'routers', data => '198.51.100.1' }
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      dhcp4 = config.fetch('Dhcp4')

      expect(dhcp4['valid-lifetime']).to eq(7200)
      expect(dhcp4['control-socket']).not_to be_nil
      expect(dhcp4.dig('loggers', 0, 'name')).to eq('kea-dhcp4')

      subnets = Array(dhcp4['subnet4'])
      legacy = subnets.find { |scope| scope.dig('user-context', 'puppet_name') == 'legacy-scope' }
      added = subnets.find { |scope| scope.dig('user-context', 'puppet_name') == 'new-scope' }

      expect(legacy).not_to be_nil
      expect(legacy.dig('user-context', 'custom_data')).to eq('should remain')
      expect(added).not_to be_nil
      expect(added['subnet']).to eq('198.51.100.0/24')
    end
  end

  context 'when multiple scopes are managed' do
    before(:each) do
      run_shell("cp #{config_path} #{config_path}.bak 2>/dev/null || true")
      run_shell("rm -f #{config_path}")
    end

    after(:each) do
      run_shell("mv #{config_path}.bak #{config_path} 2>/dev/null || true")
    end

    it 'aggregates all scopes into the same configuration file' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'subnet-a':
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
          options => [
            { name => 'routers', data => '192.0.2.1' }
          ],
          config_path => '#{config_path}',
        }

        kea_dhcp_v4_scope { 'subnet-b':
          subnet  => '198.51.100.0/24',
          pools   => ['198.51.100.10 - 198.51.100.200'],
          options => [
            { name => 'routers', data => '198.51.100.1' }
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnets = Array(config.fetch('Dhcp4').fetch('subnet4'))

      expect(subnets.size).to eq(2)
      expect(subnets.map { |scope| scope['subnet'] }).to include('192.0.2.0/24', '198.51.100.0/24')
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

    it 'preserves the original config when validation fails' do
      checksum_before = run_shell("md5sum #{config_path}").stdout.split.first

      manifest = <<~PP
        kea_dhcp_v4_scope { 'invalid-scope':
          subnet      => '192.0.2.0/24',
          pools       => ['198.51.100.10 - 198.51.100.200'], # outside the subnet
          config_path => '#{config_path}',
        }
      PP

      result = apply_manifest(manifest, catch_failures: false)
      expect(result.stderr).to match(%r{post_resource_eval failed.*Kea_dhcp_v4_scope}m)

      # Verify the original config file is unchanged
      checksum_after = run_shell("md5sum #{config_path}").stdout.split.first
      expect(checksum_after).to eq(checksum_before)
    end
  end
end
