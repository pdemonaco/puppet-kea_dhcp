# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_dhcp_v6_scope).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v6_scope) }
  let(:tempfile) { Tempfile.new('kea-dhcp6') }
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

      server_resource = Puppet::Type.type(:kea_dhcp_v6_server).new(
        name: 'dhcp6',
        config_path: config_path,
      )

      scope_resource = type_class.new(
        name: 'wired_network',
        subnet: '2001:db8:1::/64',
      )

      catalog.add_resource(server_resource, scope_resource)

      server_provider_class = Puppet::Type.type(:kea_dhcp_v6_server).provider(:json)
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
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(
        name: 'wired_network',
        subnet: '2001:db8:1::/64',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      scope = config['Dhcp6']['subnet6'].first
      expect(scope['id']).to eq(1)
      expect(scope['subnet']).to eq('2001:db8:1::/64')
      expect(scope.dig('user-context', 'puppet_name')).to eq('wired_network')
    end

    it 'uses the provided id when available' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [{ 'id' => 2, 'subnet' => '2001:db8:2::/64' }] })

      resource = type_class.new(
        name: 'new_scope',
        subnet: '2001:db8:3::/64',
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
      ids = config['Dhcp6']['subnet6'].map { |scope| scope['id'] }
      expect(ids).to contain_exactly(2, 5)
    end

    it 'writes pd-pools when provided' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(
        name: 'pd_scope',
        subnet: '2001:db8:1::/64',
        pd_pools: [{ 'prefix' => '3000:1::', 'prefix-len' => 64, 'delegated-len' => 96 }],
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      scope = config['Dhcp6']['subnet6'].first
      expect(scope['pd-pools']).to contain_exactly(
        { 'prefix' => '3000:1::', 'prefix-len' => 64, 'delegated-len' => 96 },
      )
    end

    it 'rejects duplicate subnets' do
      write_config(config_path, 'Dhcp6' => {
                     'subnet6' => [{
                       'id' => 1,
                       'subnet' => '2001:db8:1::/64',
                       'user-context' => { 'puppet_name' => 'existing' },
                     }],
                   })

      resource = type_class.new(
        name: 'duplicate',
        subnet: '2001:db8:1::/64',
        config_path: config_path,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create

      expect { provider.flush }.to raise_error(Puppet::Error, %r{Subnet 2001:db8:1::/64 is already defined})
    end
  end

  context 'when updating an existing scope' do
    it 'modifies the subnet and pools in place' do
      write_config(
        config_path,
        'Dhcp6' => {
          'subnet6' => [
            {
              'id' => 3,
              'subnet' => '2001:db8:1::/64',
              'pools' => [{ 'pool' => '2001:db8:1::1 - 2001:db8:1::ffff' }],
              'user-context' => { 'puppet_name' => 'existing' },
            },
          ],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'existing',
        id: 3,
        subnet: '2001:db8:1::/64',
        pools: ['2001:db8:1::1 - 2001:db8:1::ffff'],
        pd_pools: [],
        options: [],
        config_path: config_path,
      }

      resource = type_class.new(
        name: 'existing',
        subnet: '2001:db8:2::/64',
        pools: ['2001:db8:2::1 - 2001:db8:2::ffff'],
        config_path: config_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.subnet = '2001:db8:2::/64'
      provider.pools = ['2001:db8:2::1 - 2001:db8:2::ffff']
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      scope = config['Dhcp6']['subnet6'].first
      expect(scope['subnet']).to eq('2001:db8:2::/64')
      expect(scope['pools'].first['pool']).to eq('2001:db8:2::1 - 2001:db8:2::ffff')
    end
  end

  context 'when destroying' do
    it 'removes the scope from the configuration' do
      write_config(
        config_path,
        'Dhcp6' => {
          'subnet6' => [
            {
              'id' => 1,
              'subnet' => '2001:db8:1::/64',
              'user-context' => { 'puppet_name' => 'remove_me' },
            },
          ],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'remove_me',
        id: 1,
        subnet: '2001:db8:1::/64',
        pools: [],
        pd_pools: [],
        options: [],
        config_path: config_path,
      }

      resource = type_class.new(
        name: 'remove_me',
        subnet: '2001:db8:1::/64',
        config_path: config_path,
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_uncontrolled!

      config = JSON.parse(File.read(config_path))
      expect(config['Dhcp6']['subnet6']).to be_empty
    end
  end
end
