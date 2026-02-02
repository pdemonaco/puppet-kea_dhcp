# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp_v4_reservation provider' do
  let(:config_path) { '/etc/kea/kea-dhcp4.conf' }

  before :all do
    base_manifest = <<~PP
      class { 'kea_dhcp':
        sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
        enable_ddns           => false,
        enable_ctrl_agent     => false,
      }

      kea_dhcp_v4_scope { 'test-subnet':
        ensure  => present,
        id      => 1,
        subnet  => '192.0.2.0/24',
        pools   => ['192.0.2.10 - 192.0.2.200'],
      }
    PP
    apply_manifest(base_manifest, catch_failures: true)
  end

  context 'when creating a reservation with hw-address' do
    it 'adds the reservation to the subnet' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'server-1':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => '1a:1b:1c:1d:1e:1f',
          ip_address      => '192.0.2.100',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservations = subnet['reservations']

      expect(reservations).not_to be_nil
      expect(reservations.size).to eq(1)
      expect(reservations.first['hw-address']).to eq('1a:1b:1c:1d:1e:1f')
      expect(reservations.first['ip-address']).to eq('192.0.2.100')
    end
  end

  context 'when creating a reservation with client-id' do
    it 'adds the reservation using client-id' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'client-1':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'client-id',
          identifier      => '01:11:22:33:44:55:66',
          ip_address      => '192.0.2.101',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservation = subnet['reservations'].find { |r| r['client-id'] == '01:11:22:33:44:55:66' }

      expect(reservation).not_to be_nil
      expect(reservation['ip-address']).to eq('192.0.2.101')
    end
  end

  context 'when adding a hostname to a reservation' do
    it 'includes the hostname in the reservation' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'alice-laptop':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => '0a:0b:0c:0d:0e:0f',
          ip_address      => '192.0.2.102',
          hostname        => 'alice-laptop',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservation = subnet['reservations'].find { |r| r['hw-address'] == '0a:0b:0c:0d:0e:0f' }

      expect(reservation).not_to be_nil
      expect(reservation['hostname']).to eq('alice-laptop')
      expect(reservation['ip-address']).to eq('192.0.2.102')
    end
  end

  context 'when managing multiple reservations' do
    it 'aggregates all reservations in the same subnet' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'host-a':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => 'aa:aa:aa:aa:aa:aa',
          ip_address      => '192.0.2.50',
        }

        kea_dhcp_v4_reservation { 'host-b':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => 'bb:bb:bb:bb:bb:bb',
          ip_address      => '192.0.2.51',
          hostname        => 'host-b',
        }

        kea_dhcp_v4_reservation { 'host-c':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'client-id',
          identifier      => 'cc:cc:cc:cc:cc:cc',
          ip_address      => '192.0.2.52',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservations = subnet['reservations']

      expect(reservations.size).to be >= 3
      expect(reservations.map { |r| r['ip-address'] }).to include('192.0.2.50', '192.0.2.51', '192.0.2.52')
    end
  end

  context 'when removing a reservation' do
    before(:each) do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'temp-host':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => 'ff:ff:ff:ff:ff:ff',
          ip_address      => '192.0.2.99',
        }
      PP
      apply_manifest(manifest, catch_failures: true)
    end

    it 'removes the reservation from the subnet' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'temp-host':
          ensure          => absent,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => 'ff:ff:ff:ff:ff:ff',
          ip_address      => '192.0.2.99',
        }
      PP

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservation = subnet['reservations']&.find { |r| r['hw-address'] == 'ff:ff:ff:ff:ff:ff' }

      expect(reservation).to be_nil
    end
  end

  context 'when the configuration preserves unmanaged data' do
    it 'keeps other subnet properties intact' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'new-reservation':
          ensure          => present,
          scope_id        => 1,
          identifier_type => 'hw-address',
          identifier      => 'dd:dd:dd:dd:dd:dd',
          ip_address      => '192.0.2.201',
        }
      PP

      apply_manifest(manifest, catch_failures: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }

      expect(subnet['subnet']).to eq('192.0.2.0/24')
      expect(subnet['pools']).not_to be_empty
      expect(subnet['reservations'].find { |r| r['hw-address'] == 'dd:dd:dd:dd:dd:dd' }).not_to be_nil
    end
  end
end
