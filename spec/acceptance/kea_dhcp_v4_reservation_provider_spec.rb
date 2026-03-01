# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'kea_dhcp_v4_reservation provider' do
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
    it 'adds the reservation to the subnet by auto-detecting from IP' do
      scope_manifest = <<~PP
        kea_dhcp_v4_scope { 'test-subnet':
          ensure  => present,
          id      => 1,
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      reservation_manifest = <<~PP
        kea_dhcp_v4_reservation { 'server-1':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => '1a:1b:1c:1d:1e:1f',
          ip_address      => '192.0.2.100',
        }
      PP

      apply_manifest(scope_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_changes: true)

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
      scope_manifest = <<~PP
        kea_dhcp_v4_scope { 'test-subnet':
          ensure  => present,
          id      => 1,
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      reservation_manifest = <<~PP
        kea_dhcp_v4_reservation { 'client-1':
          ensure          => present,
          identifier_type => 'client-id',
          identifier      => '01:11:22:33:44:55:66',
          ip_address      => '192.0.2.101',
        }
      PP

      apply_manifest(scope_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservation = subnet['reservations'].find { |r| r['client-id'] == '01:11:22:33:44:55:66' }

      expect(reservation).not_to be_nil
      expect(reservation['ip-address']).to eq('192.0.2.101')
    end
  end

  context 'when adding a hostname to a reservation' do
    it 'includes the hostname in the reservation' do
      scope_manifest = <<~PP
        kea_dhcp_v4_scope { 'test-subnet':
          ensure  => present,
          id      => 1,
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      reservation_manifest = <<~PP
        kea_dhcp_v4_reservation { 'alice-laptop':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => '0a:0b:0c:0d:0e:0f',
          ip_address      => '192.0.2.102',
          hostname        => 'alice-laptop',
        }
      PP

      apply_manifest(scope_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_changes: true)

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
      scope_manifest = <<~PP
        kea_dhcp_v4_scope { 'test-subnet':
          ensure  => present,
          id      => 1,
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      reservations_manifest = <<~PP
        kea_dhcp_v4_reservation { 'host-a':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => 'aa:aa:aa:aa:aa:aa',
          ip_address      => '192.0.2.50',
        }

        kea_dhcp_v4_reservation { 'host-b':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => 'bb:bb:bb:bb:bb:bb',
          ip_address      => '192.0.2.51',
          hostname        => 'host-b',
        }

        kea_dhcp_v4_reservation { 'host-c':
          ensure          => present,
          identifier_type => 'client-id',
          identifier      => 'cc:cc:cc:cc:cc:cc',
          ip_address      => '192.0.2.52',
        }
      PP

      apply_manifest(scope_manifest, catch_failures: true)
      apply_manifest(reservations_manifest, catch_failures: true)
      apply_manifest(reservations_manifest, catch_changes: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
      reservations = subnet['reservations']

      expect(reservations.size).to be >= 3
      expect(reservations.map { |r| r['ip-address'] }).to include('192.0.2.50', '192.0.2.51', '192.0.2.52')
    end
  end

  context 'when removing a reservation' do
    before(:each) do
      scope_manifest = <<~PP
        kea_dhcp_v4_scope { 'test-subnet':
          ensure  => present,
          id      => 1,
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      reservation_manifest = <<~PP
        kea_dhcp_v4_reservation { 'temp-host':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => 'ff:ff:ff:ff:ff:ff',
          ip_address      => '192.0.2.99',
        }
      PP

      apply_manifest(scope_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_failures: true)
    end

    it 'removes the reservation from the subnet' do
      manifest = <<~PP
        kea_dhcp_v4_reservation { 'temp-host':
          ensure          => absent,
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

  context 'when the generated configuration is invalid' do
    let(:valid_config) do
      <<~JSON
        {
          "Dhcp4": {
            "valid-lifetime": 3600,
            "subnet4": [
              {
                "id": 1,
                "subnet": "192.0.2.0/24",
                "pools": [{"pool": "192.0.2.10 - 192.0.2.200"}]
              }
            ],
            "option-data": [
              {
                "name": "time-servers",
                "data": "not-an-ip-address"
              }
            ]
          }
        }
      JSON
    end

    before(:each) do
      run_shell("cp #{config_path} #{config_path}.invalid_test_bak 2>/dev/null || true")
      run_shell("cat <<'JSON' > #{config_path}\n#{valid_config}\nJSON")
    end

    after(:each) do
      run_shell("mv #{config_path}.invalid_test_bak #{config_path} 2>/dev/null || true")
    end

    it 'prints kea errors and preserves the original config when validation fails' do
      checksum_before = run_shell("md5sum #{config_path}").stdout.split.first

      manifest = <<~PP
        kea_dhcp_v4_reservation { 'trigger-validation':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => 'aa:bb:cc:dd:ee:ff',
          ip_address      => '192.0.2.150',
          config_path     => '#{config_path}',
        }
      PP

      result = apply_manifest(manifest, catch_failures: false)
      expect(result.stderr).to match(%r{Kea_dhcp_v4_commit\[#{Regexp.escape(config_path)}\]})
      expect(result.stderr).to match(%r{ERROR \[kea-dhcp4})

      checksum_after = run_shell("md5sum #{config_path}").stdout.split.first
      expect(checksum_after).to eq(checksum_before)
    end
  end

  context 'when the configuration preserves unmanaged data' do
    it 'keeps other subnet properties intact' do
      scope_manifest = <<~PP
        kea_dhcp_v4_scope { 'test-subnet':
          ensure  => present,
          id      => 1,
          subnet  => '192.0.2.0/24',
          pools   => ['192.0.2.10 - 192.0.2.200'],
        }
      PP

      reservation_manifest = <<~PP
        kea_dhcp_v4_reservation { 'new-reservation':
          ensure          => present,
          identifier_type => 'hw-address',
          identifier      => 'dd:dd:dd:dd:dd:dd',
          ip_address      => '192.0.2.201',
        }
      PP

      apply_manifest(scope_manifest, catch_failures: true)
      apply_manifest(reservation_manifest, catch_failures: true)

      config = JSON.parse(run_shell("cat #{config_path}").stdout)
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }

      expect(subnet['subnet']).to eq('192.0.2.0/24')
      expect(subnet['pools']).not_to be_empty
      expect(subnet['reservations'].find { |r| r['hw-address'] == 'dd:dd:dd:dd:dd:dd' }).not_to be_nil
    end
  end

  describe 'unix_socket provider' do
    let(:socket_path) { '/var/run/kea/kea4-ctrl-socket' }

    # Send a reservation-get command via the kea-dhcp4 control socket and
    # return the parsed JSON response.
    def socket_get_reservation(socket_path, subnet_id, identifier_type, identifier)
      result = run_shell(
        "/opt/puppetlabs/puppet/bin/ruby -e \"require 'socket'; require 'json'; " \
        "s=UNIXSocket.new('#{socket_path}'); " \
        "s.write({'command'=>'reservation-get','arguments'=>{'subnet-id'=>#{subnet_id}," \
        "'identifier-type'=>'#{identifier_type}','identifier'=>'#{identifier}'}}.to_json); " \
        's.close_write; puts s.read"',
      )
      JSON.parse(result.stdout)
    end

    before :all do
      reset_kea_configs
      install_repository

      # Apply kea_dhcp with postgresql host backend.  The kea database on the
      # instance port (5433) already contains the full Kea schema including
      # hosts tables, so no additional schema init is required.
      base_manifest = <<~PP
        class { 'kea_dhcp':
          lease_sensitive_db_password => Sensitive('LitmusP@ssw0rd!'),
          host_backend                => 'postgresql',
          host_sensitive_db_password  => Sensitive('LitmusP@ssw0rd!'),
          host_database_port          => 5433,
          enable_ddns                 => false,
          enable_ctrl_agent           => false,
        }

        kea_dhcp_v4_scope { 'test-subnet':
          ensure => present,
          id     => 1,
          subnet => '192.0.2.0/24',
          pools  => ['192.0.2.10 - 192.0.2.200'],
        }
      PP
      apply_manifest(base_manifest, catch_failures: true)

      # Inject the control-socket into the config and restart kea-dhcp4.
      # The kea_dhcp_v4_server provider preserves unmanaged keys so this
      # persists across subsequent puppet runs.
      run_shell(
        'python3 -c "import json; ' \
        "f=open('/etc/kea/kea-dhcp4.conf'); cfg=json.load(f); f.close(); " \
        "cfg['Dhcp4']['control-socket']={'socket-type':'unix','socket-name':'/var/run/kea/kea4-ctrl-socket'}; " \
        "f=open('/etc/kea/kea-dhcp4.conf','w'); json.dump(cfg,f,indent=2); f.close()\"",
      )
      run_shell('systemctl restart kea-dhcp4')
      run_shell("timeout 30 bash -c 'until [ -S /var/run/kea/kea4-ctrl-socket ]; do sleep 1; done'")
    end

    context 'when creating a reservation via the control socket' do
      let(:manifest) do
        <<~PP
          kea_dhcp_v4_reservation { 'socket-host-1':
            ensure          => present,
            identifier_type => 'hw-address',
            identifier      => '1a:1b:1c:1d:1e:1f',
            ip_address      => '192.0.2.110',
            hostname        => 'socket-host-1',
            socket_path     => '/var/run/kea/kea4-ctrl-socket',
          }
        PP
      end

      it 'applies the manifest idempotently' do
        apply_manifest(manifest, catch_failures: true)
        apply_manifest(manifest, catch_changes: true)
      end

      it 'stores the reservation in the host database, not in kea-dhcp4.conf' do
        apply_manifest(manifest, catch_failures: true)

        config = JSON.parse(run_shell("cat #{config_path}").stdout)
        subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 1 }
        reservations = Array(subnet['reservations'])

        expect(reservations.none? { |r| r['hw-address'] == '1a:1b:1c:1d:1e:1f' }).to be true
      end

      it 'can retrieve the reservation via the kea-dhcp4 control socket' do
        apply_manifest(manifest, catch_failures: true)

        response = socket_get_reservation(socket_path, 1, 'hw-address', '1a:1b:1c:1d:1e:1f')

        expect(response['result']).to eq(0)
        expect(response.dig('arguments', 'ip-address')).to eq('192.0.2.110')
        expect(response.dig('arguments', 'hostname')).to eq('socket-host-1')
      end
    end

    context 'when removing a reservation via the control socket' do
      before(:each) do
        setup_manifest = <<~PP
          kea_dhcp_v4_reservation { 'socket-host-2':
            ensure          => present,
            identifier_type => 'hw-address',
            identifier      => 'aa:bb:cc:dd:ee:ff',
            ip_address      => '192.0.2.111',
            socket_path     => '/var/run/kea/kea4-ctrl-socket',
          }
        PP
        apply_manifest(setup_manifest, catch_failures: true)
      end

      let(:absent_manifest) do
        <<~PP
          kea_dhcp_v4_reservation { 'socket-host-2':
            ensure          => absent,
            identifier_type => 'hw-address',
            identifier      => 'aa:bb:cc:dd:ee:ff',
            ip_address      => '192.0.2.111',
            socket_path     => '/var/run/kea/kea4-ctrl-socket',
          }
        PP
      end

      it 'removes the reservation idempotently' do
        apply_manifest(absent_manifest, catch_failures: true)
        apply_manifest(absent_manifest, catch_changes: true)
      end

      it 'confirms the reservation is gone via the kea-dhcp4 control socket' do
        apply_manifest(absent_manifest, catch_failures: true)

        response = socket_get_reservation(socket_path, 1, 'hw-address', 'aa:bb:cc:dd:ee:ff')

        expect(response['result']).to eq(3) # Kea result 3 = not found
      end
    end
  end
end
