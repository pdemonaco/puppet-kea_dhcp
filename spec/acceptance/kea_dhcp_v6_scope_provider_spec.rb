# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp_v6_scope provider' do
  let(:config_path) { '/etc/kea/kea-dhcp6.conf' }

  before :all do
    reset_kea_configs
    install_repository
    base_manifest = <<~PP
      class { 'kea_dhcp':
        sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
        enable_ddns           => false,
        enable_ctrl_agent     => false,
        enable_dhcp6          => true,
      }
    PP
    apply_manifest(base_manifest, catch_failures: true)
  end

  context 'when the configuration already contains unmanaged data' do
    let(:preseed_config) do
      <<~JSON
        {
          "Dhcp6": {
            "valid-lifetime": 4000,
            "renew-timer": 1000,
            "rebind-timer": 2000,
            "preferred-lifetime": 3000,
            "subnet6": [
              {
                "id": 1,
                "subnet": "2001:db8:1::/64",
                "comment": "existing scope",
                "user-context": { "puppet_name": "legacy-scope-v6", "custom_data": "should remain" },
                "pools": [
                  { "pool": "2001:db8:1::10 - 2001:db8:1::ffff" }
                ],
                "option-data": [
                  { "name": "dns-servers", "data": "2001:db8::1" }
                ]
              }
            ],
            "loggers": [
              {
                "name": "kea-dhcp6",
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
        kea_dhcp_v6_scope { 'new-scope-v6':
          ensure      => present,
          subnet      => '2001:db8:2::/64',
          pools       => ['2001:db8:2::10 - 2001:db8:2::ffff'],
          options     => [
            { name => 'dns-servers', data => '2001:db8::2' }
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      dhcp6 = config.fetch('Dhcp6')

      expect(dhcp6['valid-lifetime']).to eq(4000)
      expect(dhcp6['renew-timer']).to eq(1000)
      expect(dhcp6.dig('loggers', 0, 'name')).to eq('kea-dhcp6')

      subnets = Array(dhcp6['subnet6'])
      legacy = subnets.find { |scope| scope.dig('user-context', 'puppet_name') == 'legacy-scope-v6' }
      added  = subnets.find { |scope| scope.dig('user-context', 'puppet_name') == 'new-scope-v6' }

      expect(legacy).not_to be_nil
      expect(legacy.dig('user-context', 'custom_data')).to eq('should remain')
      expect(added).not_to be_nil
      expect(added['subnet']).to eq('2001:db8:2::/64')

      added_options = Array(added['option-data'])
      dns_opt = added_options.find { |opt| opt['name'] == 'dns-servers' }
      expect(dns_opt).not_to be_nil
      expect(dns_opt['data']).to eq('2001:db8::2')
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
        kea_dhcp_v6_scope { 'subnet-v6-a':
          subnet      => '2001:db8:1::/64',
          pools       => ['2001:db8:1::10 - 2001:db8:1::ffff'],
          config_path => '#{config_path}',
        }

        kea_dhcp_v6_scope { 'subnet-v6-b':
          subnet      => '2001:db8:2::/64',
          pools       => ['2001:db8:2::10 - 2001:db8:2::ffff'],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnets = Array(config.fetch('Dhcp6').fetch('subnet6'))

      expect(subnets.size).to eq(2)
      expect(subnets.map { |scope| scope['subnet'] }).to include('2001:db8:1::/64', '2001:db8:2::/64')
    end
  end

  context 'when managing prefix delegation pools' do
    before(:each) do
      run_shell("cp #{config_path} #{config_path}.bak 2>/dev/null || true")
      run_shell("rm -f #{config_path}")
    end

    after(:each) do
      run_shell("mv #{config_path}.bak #{config_path} 2>/dev/null || true")
    end

    it 'writes pd-pool entries to the configuration' do
      manifest = <<~PP
        kea_dhcp_v6_scope { 'pd-scope-v6':
          subnet      => '2001:db8:3::/48',
          pd_pools    => [
            {
              'prefix'        => '2001:db8:3::',
              'prefix-len'    => 48,
              'delegated-len' => 64,
            }
          ],
          config_path => '#{config_path}',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnets = Array(config.fetch('Dhcp6').fetch('subnet6'))
      pd_scope = subnets.find { |s| s['subnet'] == '2001:db8:3::/48' }

      expect(pd_scope).not_to be_nil
      pd_pools = Array(pd_scope['pd-pools'])
      expect(pd_pools.size).to eq(1)
      expect(pd_pools[0]['prefix']).to eq('2001:db8:3::')
      expect(pd_pools[0]['prefix-len']).to eq(48)
      expect(pd_pools[0]['delegated-len']).to eq(64)
    end
  end

  context 'when the generated configuration is invalid' do
    let(:valid_config) do
      <<~JSON
        {
          "Dhcp6": {
            "valid-lifetime": 4000,
            "subnet6": [
              {
                "id": 1,
                "subnet": "2001:db8:1::/64",
                "pools": [{"pool": "2001:db8:1::10 - 2001:db8:1::ffff"}]
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
        kea_dhcp_v6_scope { 'invalid-scope-v6':
          subnet      => '2001:db8:2::/64',
          pools       => ['2001:db8:3::10 - 2001:db8:3::ffff'],
          config_path => '#{config_path}',
        }
      PP

      result = apply_manifest(manifest, catch_failures: false)
      expect(result.stderr).to match(%r{post_resource_eval failed.*Kea_dhcp_v6_scope}m)

      checksum_after = run_shell("md5sum #{config_path}").stdout.split.first
      expect(checksum_after).to eq(checksum_before)
    end
  end
end
