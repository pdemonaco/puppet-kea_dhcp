# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_dhcp_v4_scope).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v4_scope) }
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

  context 'config path resolution' do
    it 'uses the server resource config path when none specified on the scope' do
      catalog = Puppet::Resource::Catalog.new

      server_resource = Puppet::Type.type(:kea_dhcp_v4_server).new(
        name: 'dhcp4',
        config_path: config_path,
      )

      scope_resource = type_class.new(
        name: 'wired_network',
        subnet: '172.24.132.0/24',
      )

      catalog.add_resource(server_resource, scope_resource)

      server_provider_class = Puppet::Type.type(:kea_dhcp_v4_server).provider(:json)
      server_provider = server_provider_class.new
      server_provider.resource = server_resource
      server_resource.provider = server_provider
      server_provider.config_path

      provider = provider_class.new
      provider.resource = scope_resource
      scope_resource.provider = provider

      expect(provider.config_path).to eq(config_path)
    end
  end

  context 'when creating a new scope' do
    it 'assigns the next available id when none provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'wired_network',
        subnet: '172.24.132.0/24',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      scope = config['Dhcp4']['subnet4'].first
      expect(scope['id']).to eq(1)
      expect(scope['subnet']).to eq('172.24.132.0/24')
      expect(scope.dig('user-context', 'puppet_name')).to eq('wired_network')
    end

    it 'uses the provided id when available' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [{ 'id' => 2, 'subnet' => '10.0.0.0/24' }] })

      resource = type_class.new(
        name: 'new_scope',
        subnet: '192.0.2.0/24',
        id: 5,
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      ids = config['Dhcp4']['subnet4'].map { |scope| scope['id'] }
      expect(ids).to contain_exactly(2, 5)
    end
  end

  context 'when updating an existing scope' do
    it 'modifies the subnet and pools in place' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 3,
              'subnet' => '192.0.2.0/24',
              'pools' => [{ 'pool' => '192.0.2.10 - 192.0.2.50' }],
              'user-context' => { 'puppet_name' => 'existing' },
            },
          ],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'existing',
        id: 3,
        subnet: '192.0.2.0/24',
        pools: ['192.0.2.10 - 192.0.2.50'],
        options: [],
        config_path: config_path,
      }

      resource = type_class.new(
        name: 'existing',
        subnet: '198.51.100.0/24',
        pools: ['198.51.100.10 - 198.51.100.20'],
        config_path: config_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.subnet = '198.51.100.0/24'
      provider.pools = ['198.51.100.10 - 198.51.100.20']
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      scope = config['Dhcp4']['subnet4'].first
      expect(scope['subnet']).to eq('198.51.100.0/24')
      expect(scope['pools'].first['pool']).to eq('198.51.100.10 - 198.51.100.20')
    end
  end

  context 'when destroying' do
    it 'removes the scope from the configuration' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '203.0.113.0/24',
              'user-context' => { 'puppet_name' => 'remove_me' },
            },
          ],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'remove_me',
        id: 1,
        subnet: '203.0.113.0/24',
        pools: [],
        options: [],
        config_path: config_path,
      }

      resource = type_class.new(
        name: 'remove_me',
        subnet: '203.0.113.0/24',
        config_path: config_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      expect(config['Dhcp4']['subnet4']).to be_empty
    end
  end
end
