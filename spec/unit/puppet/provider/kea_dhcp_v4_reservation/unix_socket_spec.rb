# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'

provider_class = Puppet::Type.type(:kea_dhcp_v4_reservation).provider(:unix_socket)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v4_reservation) }
  let(:tempfile) { Tempfile.new('kea-dhcp4') }
  let(:config_path) { tempfile.path }
  let(:socket_path) { '/var/run/kea/kea4-ctrl-socket-test' }

  before(:each) do
    tempfile.close
    provider_class.clear_state!
    # Stub the socket file existence check
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(socket_path).and_return(true)
  end

  after(:each) do
    File.delete(config_path) if File.exist?(config_path)
  end

  def write_config(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end

  def stub_command(command, arguments, result:, response:)
    allow(described_class).to receive(:send_command)
      .with(socket_path, command, arguments)
      .and_return({ 'result' => result, 'text' => response.is_a?(String) ? response : 'ok',
                    'arguments' => response.is_a?(Hash) ? response : nil }.compact)
  end

  def stub_not_found(command, arguments)
    allow(described_class).to receive(:send_command)
      .with(socket_path, command, arguments)
      .and_return({ 'result' => 3, 'text' => 'Host not found.' })
  end

  context 'when creating a new reservation' do
    it 'calls reservation-add via the control socket' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      # Not found by ip-address
      stub_not_found('reservation-get', { 'subnet-id' => 1, 'ip-address' => '192.0.2.30' })
      # Not found by identifier
      stub_not_found('reservation-get',
                     { 'subnet-id' => 1, 'identifier-type' => 'hw-address', 'identifier' => 'a1:b2:c3:d4:e5:f6' })
      # Add succeeds
      stub_command('reservation-add',
                   { 'reservation' => { 'subnet-id' => 1, 'hw-address' => 'a1:b2:c3:d4:e5:f6',
                                        'ip-address' => '192.0.2.30', 'hostname' => 'laptop' } },
                   result: 0, response: 'Host added.')

      resource = type_class.new(
        name: 'laptop',
        identifier_type: 'hw-address',
        identifier: 'a1:b2:c3:d4:e5:f6',
        ip_address: '192.0.2.30',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush

      expect(provider.exists?).to be true
      expect(provider.ip_address).to eq('192.0.2.30')
      expect(provider.identifier).to eq('a1:b2:c3:d4:e5:f6')
    end

    it 'auto-detects subnet from ip_address' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '10.0.0.0/24' },
            { 'id' => 2, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      stub_not_found('reservation-get', { 'subnet-id' => 2, 'ip-address' => '192.0.2.50' })
      stub_not_found('reservation-get',
                     { 'subnet-id' => 2, 'identifier-type' => 'hw-address', 'identifier' => 'aa:bb:cc:dd:ee:ff' })
      stub_command('reservation-add',
                   { 'reservation' => { 'subnet-id' => 2, 'hw-address' => 'aa:bb:cc:dd:ee:ff',
                                        'ip-address' => '192.0.2.50', 'hostname' => 'host2' } },
                   result: 0, response: 'Host added.')

      resource = type_class.new(
        name: 'host2',
        identifier_type: 'hw-address',
        identifier: 'aa:bb:cc:dd:ee:ff',
        ip_address: '192.0.2.50',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush

      expect(provider.scope_id).to eq(2)
    end
  end

  context 'when updating an existing reservation' do
    it 'calls reservation-update when ip_address changes' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
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
      }

      # ip not taken by another reservation
      stub_not_found('reservation-get', { 'subnet-id' => 1, 'ip-address' => '192.0.2.150' })
      # current reservation found by identifier
      allow(described_class).to receive(:send_command)
        .with(socket_path, 'reservation-get',
              { 'subnet-id' => 1, 'identifier-type' => 'hw-address', 'identifier' => '1a:1b:1c:1d:1e:1f' })
        .and_return({
                      'result' => 0,
                      'arguments' => { 'hw-address' => '1a:1b:1c:1d:1e:1f', 'ip-address' => '192.0.2.100',
                                       'subnet-id' => 1 },
                    })
      stub_command('reservation-update',
                   { 'reservation' => { 'subnet-id' => 1, 'hw-address' => '1a:1b:1c:1d:1e:1f',
                                        'ip-address' => '192.0.2.150', 'hostname' => 'server-1' } },
                   result: 0, response: 'Host updated.')

      resource = type_class.new(
        name: 'server-1',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.150',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.ip_address = '192.0.2.150'
      provider.flush

      expect(provider.ip_address).to eq('192.0.2.150')
    end
  end

  context 'when destroying a reservation' do
    it 'calls reservation-del via the control socket' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
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
      }

      stub_command('reservation-del',
                   { 'subnet-id' => 1, 'identifier-type' => 'hw-address', 'identifier' => '1a:1b:1c:1d:1e:1f' },
                   result: 0, response: 'Host deleted.')

      resource = type_class.new(
        name: 'remove-me',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush

      expect(provider.exists?).to be false
    end

    it 'treats not-found (result 3) as success for absent' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'already-gone',
        scope_id: 1,
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        hostname: nil,
      }

      allow(described_class).to receive(:send_command)
        .with(socket_path, 'reservation-del', anything)
        .and_return({ 'result' => 3, 'text' => 'Host not found.' })

      resource = type_class.new(
        name: 'already-gone',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      expect { provider.flush }.not_to raise_error
    end
  end

  context 'when the control socket is not available' do
    before(:each) do
      allow(File).to receive(:exist?).with(socket_path).and_return(false)
    end

    it 'raises an error during flush' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
        },
      )

      resource = type_class.new(
        name: 'orphan',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{control socket.*not found})
    end

    it 'skips the resource during prefetch' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
        },
      )

      resource = type_class.new(
        name: 'skipped',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
        socket_path: socket_path,
      )
      original_provider = resource.provider
      resources = { 'skipped' => resource }

      provider_class.prefetch(resources)

      expect(resource.provider).to eq(original_provider)
    end
  end

  context 'uniqueness validation' do
    it 'raises an error when ip_address is reserved by a different identifier' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
        },
      )

      # ip-address is already taken by a different hw-address
      allow(described_class).to receive(:send_command)
        .with(socket_path, 'reservation-get', { 'subnet-id' => 1, 'ip-address' => '192.0.2.100' })
        .and_return({
                      'result' => 0,
                      'arguments' => { 'hw-address' => 'ff:ee:dd:cc:bb:aa', 'ip-address' => '192.0.2.100',
                                       'subnet-id' => 1 },
                    })

      resource = type_class.new(
        name: 'conflict',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '192.0.2.100',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{ip-address.*already exists})
    end
  end

  context 'when subnet is not found' do
    it 'raises an error when IP does not match any subnet' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [{ 'id' => 1, 'subnet' => '192.0.2.0/24' }],
        },
      )

      resource = type_class.new(
        name: 'no-match',
        identifier_type: 'hw-address',
        identifier: '1a:1b:1c:1d:1e:1f',
        ip_address: '10.0.0.100',
        config_path: config_path,
        socket_path: socket_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{Cannot find subnet containing IP address 10\.0\.0\.100})
    end
  end

  describe '.instances' do
    it 'returns an empty array' do
      expect(provider_class.instances).to eq([])
    end
  end

  describe '#exists?' do
    it 'returns true when ensure is present' do
      provider = provider_class.new(ensure: :present, name: 'test')
      expect(provider.exists?).to be true
    end

    it 'returns false for a new provider with no property_hash' do
      provider = provider_class.new
      expect(provider.exists?).to be false
    end
  end
end
