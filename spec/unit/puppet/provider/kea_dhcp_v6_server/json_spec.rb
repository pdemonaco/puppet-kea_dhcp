# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_dhcp_v6_server).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v6_server) }
  let(:tempfile) { Tempfile.new('kea-dhcp6-server') }
  let(:config_path) { tempfile.path }
  let(:sensitive_password) { Puppet::Pops::Types::PSensitiveType::Sensitive.new('kea_password') }
  let(:lease_db) do
    {
      'type' => 'postgresql',
      'name' => 'kea_dhcp',
      'user' => 'kea',
      'password' => 'kea_password',
      'host' => '127.0.0.1',
      'port' => 5433,
    }
  end

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

  def read_config(path)
    JSON.parse(File.read(path))
  end

  context 'when creating server configuration' do
    it 'writes option-data and lease-database entries' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(
        name: 'dhcp6',
        config_path: config_path,
        options: [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        lease_database: lease_db.merge('password' => sensitive_password),
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      dhcp6 = config['Dhcp6']

      expect(dhcp6['lease-database']).to include('type' => 'postgresql', 'user' => 'kea', 'password' => 'kea_password')
      expect(dhcp6['lease-database']['port']).to eq(5433)
      expect(dhcp6['option-data']).to contain_exactly({ 'name' => 'dns-servers', 'data' => '2001:db8::1' })
      expect(dhcp6['subnet6']).to eq([])
    end

    it 'writes hooks-libraries when provided' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(
        name: 'dhcp6',
        config_path: config_path,
        lease_database: lease_db,
        hooks_libraries: [
          { 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' },
          { 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so', 'parameters' => { 'enabled' => true } },
        ],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      dhcp6 = config['Dhcp6']

      expect(dhcp6['hooks-libraries']).to contain_exactly(
        { 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' },
        { 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so', 'parameters' => { 'enabled' => true } },
      )
    end

    it 'does not write hooks-libraries key when empty' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(
        name: 'dhcp6',
        config_path: config_path,
        lease_database: lease_db,
        hooks_libraries: [],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      expect(config['Dhcp6']).not_to have_key('hooks-libraries')
    end
  end

  context 'when updating server configuration' do
    it 'replaces options and lease database values' do
      write_config(
        config_path,
        'Dhcp6' => {
          'lease-database' => lease_db.merge('password' => 'old'),
          'option-data' => [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp6',
        config_path: config_path,
        options: [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        lease_database: lease_db.merge('password' => 'old'),
      }

      resource = type_class.new(
        name: 'dhcp6',
        config_path: config_path,
        options: [{ 'name' => 'dns-servers', 'data' => '2001:db8::2' }],
        lease_database: lease_db.merge('password' => Puppet::Pops::Types::PSensitiveType::Sensitive.new('new_secret')),
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.options = [{ 'name' => 'dns-servers', 'data' => '2001:db8::2' }]
      provider.lease_database = lease_db.merge('password' => 'new_secret')
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      dhcp6 = config['Dhcp6']

      expect(dhcp6['lease-database']['password']).to eq('new_secret')
      expect(dhcp6['option-data']).to contain_exactly({ 'name' => 'dns-servers', 'data' => '2001:db8::2' })
    end

    it 'updates hooks_libraries' do
      write_config(
        config_path,
        'Dhcp6' => {
          'lease-database' => lease_db,
          'hooks-libraries' => [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp6',
        config_path: config_path,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        lease_database: lease_db,
      }

      resource = type_class.new(
        name: 'dhcp6',
        config_path: config_path,
        lease_database: lease_db,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so' }],
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.hooks_libraries = [{ 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so' }]
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      expect(config['Dhcp6']['hooks-libraries']).to contain_exactly(
        { 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so' },
      )
    end
  end

  context 'when destroying server configuration' do
    it 'removes the option and lease database keys' do
      write_config(
        config_path,
        'Dhcp6' => {
          'lease-database' => lease_db,
          'option-data' => [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp6',
        config_path: config_path,
        options: [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        lease_database: lease_db,
      }

      resource = type_class.new(name: 'dhcp6', config_path: config_path, lease_database: lease_db)

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      expect(config['Dhcp6']).not_to have_key('lease-database')
      expect(config['Dhcp6']).not_to have_key('option-data')
    end

    it 'removes hooks-libraries when destroying' do
      write_config(
        config_path,
        'Dhcp6' => {
          'lease-database' => lease_db,
          'hooks-libraries' => [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp6',
        config_path: config_path,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        lease_database: lease_db,
      }

      resource = type_class.new(name: 'dhcp6', config_path: config_path, lease_database: lease_db)

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      expect(config['Dhcp6']).not_to have_key('hooks-libraries')
    end
  end

  describe '#exists?' do
    it 'returns true when ensure is present' do
      provider = provider_class.new(ensure: :present, name: 'dhcp6')

      expect(provider.exists?).to be true
    end

    it 'returns false when ensure is absent' do
      provider = provider_class.new(ensure: :absent, name: 'dhcp6')

      expect(provider.exists?).to be false
    end

    it 'returns false for a new provider with no property_hash' do
      provider = provider_class.new

      expect(provider.exists?).to be false
    end
  end

  describe '.instances' do
    let(:instances_tempfile) { Tempfile.new('kea-instances') }
    let(:instances_config_path) { instances_tempfile.path }

    before(:each) do
      instances_tempfile.close
      stub_const('PuppetX::KeaDhcp::Provider::Dhcp6Json::DEFAULT_CONFIG_PATH', instances_config_path)
    end

    after(:each) do
      File.delete(instances_config_path) if File.exist?(instances_config_path)
    end

    it 'returns an empty array when no server configuration exists' do
      write_config(instances_config_path, 'Dhcp6' => { 'subnet6' => [] })

      instances = provider_class.instances

      expect(instances).to eq([])
    end

    it 'returns an instance when lease-database is present' do
      write_config(
        instances_config_path,
        'Dhcp6' => { 'lease-database' => lease_db },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:name)).to eq('dhcp6')
      expect(instances[0].get(:lease_database)).to eq(lease_db)
    end

    it 'returns an instance when option-data is present' do
      write_config(
        instances_config_path,
        'Dhcp6' => { 'option-data' => [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }] },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:options)).to eq([{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }])
    end

    it 'returns an instance when hooks-libraries is present' do
      write_config(
        instances_config_path,
        'Dhcp6' => { 'hooks-libraries' => [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }] },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:hooks_libraries)).to eq([{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }])
    end

    it 'deep stringifies hooks_libraries parameters' do
      write_config(
        instances_config_path,
        'Dhcp6' => {
          'hooks-libraries' => [{
            'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so',
            'parameters' => { 'nested' => { 'key' => 'value' } },
          }],
        },
      )

      instances = provider_class.instances

      expect(instances[0].get(:hooks_libraries)).to eq([{
                                                         'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so',
                                                         'parameters' => { 'nested' => { 'key' => 'value' } },
                                                       }])
    end
  end

  describe '.prefetch' do
    it 'populates providers for matching resources' do
      write_config(
        config_path,
        'Dhcp6' => {
          'lease-database' => lease_db,
          'option-data' => [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        },
      )

      resource = type_class.new(name: 'dhcp6', config_path: config_path, lease_database: lease_db)
      resources = { 'dhcp6' => resource }

      provider_class.prefetch(resources)

      expect(resource.provider).not_to be_nil
      expect(resource.provider.get(:ensure)).to eq(:present)
      expect(resource.provider.get(:options)).to eq([{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }])
    end

    it 'does not set provider when server config is absent' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(name: 'dhcp6', config_path: config_path, lease_database: lease_db)
      original_provider = resource.provider
      resources = { 'dhcp6' => resource }

      provider_class.prefetch(resources)

      expect(resource.provider).to eq(original_provider)
    end
  end

  describe '.present?' do
    it 'returns true when lease-database key exists' do
      expect(provider_class.present?({ 'lease-database' => {} })).to be true
    end

    it 'returns true when option-data key exists' do
      expect(provider_class.present?({ 'option-data' => [] })).to be true
    end

    it 'returns true when hooks-libraries key exists' do
      expect(provider_class.present?({ 'hooks-libraries' => [] })).to be true
    end

    it 'returns false when no server keys exist' do
      expect(provider_class.present?({ 'subnet6' => [] })).to be false
    end

    it 'returns false for empty hash' do
      expect(provider_class.present?({})).to be false
    end
  end

  describe 'property accessors' do
    let(:provider) do
      provider_class.new(
        ensure: :present,
        name: 'dhcp6',
        options: [{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }],
        hooks_libraries: [{ 'library' => '/path/to/lib.so' }],
        lease_database: lease_db,
      )
    end

    it 'returns options from property_hash' do
      expect(provider.options).to eq([{ 'name' => 'dns-servers', 'data' => '2001:db8::1' }])
    end

    it 'returns hooks_libraries from property_hash' do
      expect(provider.hooks_libraries).to eq([{ 'library' => '/path/to/lib.so' }])
    end

    it 'returns lease_database from property_hash' do
      expect(provider.lease_database).to eq(lease_db)
    end
  end

  describe '#flush with empty state' do
    it 'does nothing when property_flush and property_hash are both empty' do
      write_config(config_path, 'Dhcp6' => { 'subnet6' => [] })

      resource = type_class.new(name: 'dhcp6', config_path: config_path, lease_database: lease_db)
      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      original_content = File.read(config_path)
      provider.flush

      expect(File.read(config_path)).to eq(original_content)
    end
  end
end
