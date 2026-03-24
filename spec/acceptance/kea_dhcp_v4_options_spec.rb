# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'option array data' do
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

  context 'when a scope is created with array option data' do
    before(:each) do
      run_shell("rm -f #{config_path}")
    end

    it 'writes the values as a CSV string and is idempotent' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'array-opts-scope':
          ensure      => present,
          subnet      => '192.0.2.0/24',
          pools       => ['192.0.2.10 - 192.0.2.200'],
          options     => [
            { name => 'domain-name-servers', data => ['1.1.1.1', '8.8.8.8'] },
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      scope = config['Dhcp4']['subnet4'].find { |s| s.dig('user-context', 'puppet_name') == 'array-opts-scope' }

      expect(scope).not_to be_nil
      expect(scope['option-data']).to contain_exactly(
        { 'name' => 'domain-name-servers', 'data' => '1.1.1.1, 8.8.8.8' },
      )
    end
  end

  context 'when the server is created with array option data' do
    before(:each) do
      run_shell("rm -f #{config_path}")
    end

    it 'writes the values as a CSV string and is idempotent' do
      manifest = <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
          array_dhcp4_server_options  => [
            { 'name' => 'domain-name-servers', 'data' => ['1.1.1.1', '8.8.8.8'] },
          ],
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      opts = Array(config['Dhcp4']['option-data'])

      expect(opts).to include({ 'name' => 'domain-name-servers', 'data' => '1.1.1.1, 8.8.8.8' })
    end
  end

  context 'when a scope has pre-existing CSV option data on disk' do
    let(:preseed_config) do
      <<~JSON
        {
          "Dhcp4": {
            "subnet4": [
              {
                "id": 1,
                "subnet": "192.0.2.0/24",
                "pools": [{ "pool": "192.0.2.10 - 192.0.2.200" }],
                "user-context": { "puppet_name": "preseed-scope" },
                "option-data": [
                  { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
                ]
              }
            ]
          }
        }
      JSON
    end

    before(:each) do
      run_shell("cat <<'JSON' > #{config_path}\n#{preseed_config}\nJSON")
    end

    it 'treats the CSV data as in sync with the equivalent array form' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'preseed-scope':
          ensure      => present,
          subnet      => '192.0.2.0/24',
          pools       => ['192.0.2.10 - 192.0.2.200'],
          options     => [
            { name => 'domain-name-servers', data => ['1.1.1.1', '8.8.8.8'] },
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_changes: true)
    end

    it 'updates the on-disk CSV when the array values change, and is then idempotent' do
      manifest = <<~PP
        kea_dhcp_v4_scope { 'preseed-scope':
          ensure      => present,
          subnet      => '192.0.2.0/24',
          pools       => ['192.0.2.10 - 192.0.2.200'],
          options     => [
            { name => 'domain-name-servers', data => ['9.9.9.9', '8.8.8.8'] },
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      scope = config['Dhcp4']['subnet4'].find { |s| s.dig('user-context', 'puppet_name') == 'preseed-scope' }

      expect(scope).not_to be_nil
      expect(scope['option-data']).to contain_exactly(
        { 'name' => 'domain-name-servers', 'data' => '9.9.9.9, 8.8.8.8' },
      )
    end
  end
end
