# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp class on Rocky 9' do
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
      expect(apply_manifest(manifest, catch_failures: true, debug: true).exit_code).to be_zero
      apply_mainifest(manifest, catch_changes: true)
    end

    describe package('isc-kea') do
      it { is_expected.to be_installed }

      it 'installs kea 3.0.x' do
        version = run_shell("rpm -q --qf '%{VERSION}' isc-kea").stdout.strip
        expect(version).to match(%r{\A3\.0\.})
      end
    end

    it 'creates the PostgreSQL database for leases' do
      query = "SELECT 1 FROM pg_database WHERE datname = 'kea_dhcp';"
      result = run_shell("su - postgres -c \"psql -tAc \\\"#{query}\\\"\"")
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

      expect(lease_db['name']).to eq('kea_dhcp')
      expect(lease_db['user']).to eq('kea')
      expect(lease_db['port']).to eq(5433)

      server_options = Array(dhcp4['option-data'])
      router_option = server_options.find { |opt| opt['name'] == 'routers' }
      expect(router_option).not_to be_nil
      expect(router_option['data']).to eq('192.0.2.1')
    end
  end
end
