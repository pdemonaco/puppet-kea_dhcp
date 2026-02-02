# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_dhcp_v4_reservation).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v4_reservation) }
  let(:tempfile) { Tempfile.new('kea-dhcp4') }
  let(:config_path) { tempfile.path }

  before(:each) do
    tempfile.close
    provider_class.clear_state!
    allow(Puppet::Util::Execution).to receive(:execute).and_return('')
  end

  after(:each) do
    File.delete(config_path) if File.exist?(config_path)
  end

  def write_config(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end

  context 'when creating a new reservation with hw-address' do
    it 'adds the reservation to the subnet by auto-detecting from IP' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      resource = type_class.new(
        name: 'server-1',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      subnet = config['Dhcp4']['subnet4'].first
      reservations = subnet['reservations']

      expect(reservations).not_to be_nil
      expect(reservations.size).to eq(1)
      expect(reservations.first['hw-address']).to eq('1a:1b:1c:1d:1e:1f')
      expect(reservations.first['ip-address']).to eq('192.0.2.100')
      expect(reservations.first.dig('user-context', 'puppet_name')).to eq('server-1')
    end

    it 'adds the reservation with hostname' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      resource = type_class.new(
        name: 'alice-laptop',
        identifier_type: 'hw-address',
        identifier: '0a:0b:0c:0d:0e:0f',
        ip_address: '192.0.2.101',
        hostname: 'alice-laptop',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      subnet = config['Dhcp4']['subnet4'].first
      reservation = subnet['reservations'].first

      expect(reservation['hw-address']).to eq('0a:0b:0c:0d:0e:0f')
      expect(reservation['ip-address']).to eq('192.0.2.101')
      expect(reservation['hostname']).to eq('alice-laptop')
    end
  end

  context 'when creating a reservation with client-id' do
    it 'adds the reservation using client-id identifier' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      resource = type_class.new(
        name: 'client-1',
        identifier_type: 'client-id',
        identifier: '01:11:22:33:44:55:66',
        ip_address: '192.0.2.102',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      reservation = config['Dhcp4']['subnet4'].first['reservations'].first

      expect(reservation['client-id']).to eq('01:11:22:33:44:55:66')
      expect(reservation['ip-address']).to eq('192.0.2.102')
      expect(reservation.key?('hw-address')).to be false
    end
  end

  context 'when updating an existing reservation' do
    it 'modifies the IP address in place' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                {
                  'hw-address' => '1a:1b:1c:1d:1e:1f',
                  'ip-address' => '192.0.2.100',
                  'user-context' => { 'puppet_name' => 'server-1' },
                },
              ],
            },
          ],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'server-1',
        scope_id: 1,
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        hostname: nil,
        config_path: config_path,
      }

      resource = type_class.new(
        name: 'server-1',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.150',
        config_path: config_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.ip_address = '192.0.2.150'
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      reservation = config['Dhcp4']['subnet4'].first['reservations'].first

      expect(reservation['ip-address']).to eq('192.0.2.150')
      expect(reservation['hw-address']).to eq('1a:1b:1c:1d:1e:1f')
    end
  end

  context 'when destroying a reservation' do
    it 'removes the reservation from the subnet' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                {
                  'hw-address' => '1a:1b:1c:1d:1e:1f',
                  'ip-address' => '192.0.2.100',
                  'user-context' => { 'puppet_name' => 'remove-me' },
                },
              ],
            },
          ],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'remove-me',
        scope_id: 1,
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        hostname: nil,
        config_path: config_path,
      }

      resource = type_class.new(
        name: 'remove-me',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      reservations = config['Dhcp4']['subnet4'].first['reservations']

      expect(reservations).to be_empty
    end
  end

  context 'uniqueness validation' do
    it 'prevents duplicate hw-address in the same subnet' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                {
                  'hw-address' => '1a:1b:1c:1d:1e:1f',
                  'ip-address' => '192.0.2.100',
                },
              ],
            },
          ],
        },
      )

      # Clear state after writing config to ensure cache is fresh
      provider_class.clear_state!

      resource = type_class.new(
        name: 'duplicate',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.101',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{hw-address.*already exists})
    end

    it 'prevents duplicate ip-address in the same subnet' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                {
                  'hw-address' => '1a:1b:1c:1d:1e:1f',
                  'ip-address' => '192.0.2.100',
                },
              ],
            },
          ],
        },
      )

      provider_class.clear_state!

      resource = type_class.new(
        name: 'duplicate-ip',
        identifier_type: 'hw-address',
        identifier: '2a:2b:2c:2d:2e:2f',
        ip_address: '192.0.2.100',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{ip-address.*already exists})
    end

    it 'prevents duplicate hostname in the same subnet' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                {
                  'hw-address' => '1a:1b:1c:1d:1e:1f',
                  'ip-address' => '192.0.2.100',
                  'hostname' => 'server-1',
                },
              ],
            },
          ],
        },
      )

      provider_class.clear_state!

      resource = type_class.new(
        name: 'duplicate-hostname',
        identifier_type: 'hw-address',
        identifier: '2a:2b:2c:2d:2e:2f',
        ip_address: '192.0.2.101',
        hostname: 'server-1',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{hostname.*already exists})
    end
  end

  context 'with multiple subnets' do
    it 'auto-detects the correct subnet from IP address' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
            { 'id' => 2, 'subnet' => '10.0.0.0/24' },
            { 'id' => 3, 'subnet' => '172.16.0.0/16' },
          ],
        },
      )

      resource = type_class.new(
        name: 'auto-detect',
        identifier_type: 'hw-address',
        identifier: 'aa:bb:cc:dd:ee:ff',
        ip_address: '172.16.5.10',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      subnet = config['Dhcp4']['subnet4'].find { |s| s['id'] == 3 }
      reservation = subnet['reservations'].first

      expect(reservation['hw-address']).to eq('aa:bb:cc:dd:ee:ff')
      expect(reservation['ip-address']).to eq('172.16.5.10')
    end
  end

  context 'when the subnet does not exist' do
    it 'raises an error with explicit scope_id' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      resource = type_class.new(
        name: 'orphan',
        scope_id: 99,
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{Cannot find subnet with id 99})
    end

    it 'raises an error when IP address does not match any subnet' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      resource = type_class.new(
        name: 'no-match',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '10.0.0.100',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{Cannot find subnet containing IP address 10\.0\.0\.100})
    end
  end
end
