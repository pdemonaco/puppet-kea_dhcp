# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_dhcp_v4_server).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v4_server) }
  let(:tempfile) { Tempfile.new('kea-dhcp4-server') }
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

  let(:host_db) do
    {
      'type' => 'postgresql',
      'name' => 'kea_hosts',
      'user' => 'kea',
      'password' => 'host_password',
      'host' => '127.0.0.1',
      'port' => 5432,
    }
  end

  before(:each) do
    tempfile.close
    provider_class.clear_state!
    execution_result = double('execution_result', exitstatus: 0, to_s: '')
    allow(Puppet::Util::Execution).to receive(:execute).and_return(execution_result)
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
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        options: [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        lease_database: lease_db.merge('password' => sensitive_password),
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      dhcp4 = config['Dhcp4']

      expect(dhcp4['lease-database']).to include('type' => 'postgresql', 'user' => 'kea', 'password' => 'kea_password')
      expect(dhcp4['lease-database']['port']).to eq(5433)
      expect(dhcp4['option-data']).to contain_exactly({ 'name' => 'routers', 'data' => '10.0.0.1' })
      expect(dhcp4['subnet4']).to eq([])
    end

    it 'writes hooks-libraries when provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
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
      provider_class.commit_all!

      config = read_config(config_path)
      dhcp4 = config['Dhcp4']

      expect(dhcp4['hooks-libraries']).to contain_exactly(
        { 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' },
        { 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so', 'parameters' => { 'enabled' => true } },
      )
    end

    it 'writes hosts-database when provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        host_database: host_db,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']['hosts-database']).to include(
        'type' => 'postgresql',
        'name' => 'kea_hosts',
        'user' => 'kea',
        'password' => 'host_password',
        'host' => '127.0.0.1',
        'port' => 5432,
      )
    end

    it 'does not write hosts-database key when not provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('hosts-database')
    end

    it 'does not write hooks-libraries key when empty' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        hooks_libraries: [],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('hooks-libraries')
    end

    it 'writes dhcp-ddns configuration when provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        dhcp_ddns: {
          'enable-updates' => true,
          'server-ip' => '127.0.0.1',
          'server-port' => 53_001,
          'ddns-send-updates' => true,
        },
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      dhcp4 = config['Dhcp4']

      expect(dhcp4['dhcp-ddns']).to include(
        'enable-updates' => true,
        'server-ip' => '127.0.0.1',
        'server-port' => 53_001,
        'ddns-send-updates' => true,
      )
    end

    it 'writes interfaces-config with default all-interfaces' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']['interfaces-config']).to eq({ 'interfaces' => ['*'] })
    end

    it 'writes interfaces-config with explicit interfaces' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        interfaces_config: { 'interfaces' => ['enp5s0', 'enp6s0'] },
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']['interfaces-config']).to eq({ 'interfaces' => ['enp5s0', 'enp6s0'] })
    end

    it 'writes interfaces-config with dhcp-socket-type' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        interfaces_config: { 'interfaces' => ['*'], 'dhcp-socket-type' => 'udp' },
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']['interfaces-config']).to eq({ 'interfaces' => ['*'], 'dhcp-socket-type' => 'udp' })
    end

    it 'does not write interfaces-config key when empty' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        interfaces_config: {},
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('interfaces-config')
    end

    it 'does not write dhcp-ddns key when empty' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        dhcp_ddns: {},
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('dhcp-ddns')
    end
  end

  context 'when updating server configuration' do
    it 'replaces options and lease database values' do
      write_config(
        config_path,
        'Dhcp4' => {
          'lease-database' => lease_db.merge('password' => 'old'),
          'option-data' => [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp4',
        config_path: config_path,
        options: [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        lease_database: lease_db.merge('password' => 'old'),
      }

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        options: [{ 'name' => 'domain-name-servers', 'data' => '8.8.8.8' }],
        lease_database: lease_db.merge('password' => Puppet::Pops::Types::PSensitiveType::Sensitive.new('new_secret')),
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.options = [{ 'name' => 'domain-name-servers', 'data' => '8.8.8.8' }]
      provider.lease_database = lease_db.merge('password' => 'new_secret')
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      dhcp4 = config['Dhcp4']

      expect(dhcp4['lease-database']['password']).to eq('new_secret')
      expect(dhcp4['option-data']).to contain_exactly({ 'name' => 'domain-name-servers', 'data' => '8.8.8.8' })
    end

    it 'updates hooks_libraries' do
      write_config(
        config_path,
        'Dhcp4' => {
          'lease-database' => lease_db,
          'hooks-libraries' => [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp4',
        config_path: config_path,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        lease_database: lease_db,
      }

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so' }],
      )

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.hooks_libraries = [{ 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so' }]
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']['hooks-libraries']).to contain_exactly(
        { 'library' => '/usr/lib/kea/hooks/libdhcp_stat_cmds.so' },
      )
    end
  end

  context 'when destroying server configuration' do
    it 'removes the option and lease database keys' do
      write_config(
        config_path,
        'Dhcp4' => {
          'lease-database' => lease_db,
          'option-data' => [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp4',
        config_path: config_path,
        options: [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        lease_database: lease_db,
      }

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('lease-database')
      expect(config['Dhcp4']).not_to have_key('option-data')
    end

    it 'removes hooks-libraries when destroying' do
      write_config(
        config_path,
        'Dhcp4' => {
          'lease-database' => lease_db,
          'hooks-libraries' => [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp4',
        config_path: config_path,
        hooks_libraries: [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }],
        lease_database: lease_db,
      }

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('hooks-libraries')
    end

    it 'removes hosts-database when destroying' do
      write_config(
        config_path,
        'Dhcp4' => {
          'lease-database' => lease_db,
          'hosts-database' => host_db,
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        host_database: host_db,
      }

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('hosts-database')
    end

    it 'removes interfaces-config when destroying' do
      write_config(
        config_path,
        'Dhcp4' => {
          'lease-database' => lease_db,
          'interfaces-config' => { 'interfaces' => ['enp5s0'] },
        },
      )

      property_hash = {
        ensure: :present,
        name: 'dhcp4',
        config_path: config_path,
        interfaces_config: { 'interfaces' => ['enp5s0'] },
        lease_database: lease_db,
      }

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)

      provider = provider_class.new(property_hash)
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('interfaces-config')
    end
  end

  describe '#exists?' do
    it 'returns true when ensure is present' do
      provider = provider_class.new(ensure: :present, name: 'dhcp4')

      expect(provider.exists?).to be true
    end

    it 'returns false when ensure is absent' do
      provider = provider_class.new(ensure: :absent, name: 'dhcp4')

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
      stub_const('PuppetX::KeaDhcp::Provider::Dhcp4Json::DEFAULT_CONFIG_PATH', instances_config_path)
    end

    after(:each) do
      File.delete(instances_config_path) if File.exist?(instances_config_path)
    end

    it 'returns an empty array when no server configuration exists' do
      write_config(instances_config_path, 'Dhcp4' => { 'subnet4' => [] })

      instances = provider_class.instances

      expect(instances).to eq([])
    end

    it 'returns an instance when lease-database is present' do
      write_config(
        instances_config_path,
        'Dhcp4' => { 'lease-database' => lease_db },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:name)).to eq('dhcp4')
      expect(instances[0].get(:lease_database)).to eq(lease_db)
    end

    it 'returns an instance when option-data is present' do
      write_config(
        instances_config_path,
        'Dhcp4' => { 'option-data' => [{ 'name' => 'routers', 'data' => '10.0.0.1' }] },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:options)).to eq([{ 'name' => 'routers', 'data' => '10.0.0.1' }])
    end

    it 'returns an instance when hooks-libraries is present' do
      write_config(
        instances_config_path,
        'Dhcp4' => { 'hooks-libraries' => [{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }] },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:hooks_libraries)).to eq([{ 'library' => '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' }])
    end

    it 'returns an instance when interfaces-config is present' do
      write_config(
        instances_config_path,
        'Dhcp4' => { 'interfaces-config' => { 'interfaces' => ['enp5s0'] } },
      )

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:interfaces_config)).to eq({ 'interfaces' => ['enp5s0'] })
    end

    it 'deep stringifies hooks_libraries parameters' do
      write_config(
        instances_config_path,
        'Dhcp4' => {
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
        'Dhcp4' => {
          'lease-database' => lease_db,
          'option-data' => [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        },
      )

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)
      resources = { 'dhcp4' => resource }

      provider_class.prefetch(resources)

      expect(resource.provider).not_to be_nil
      expect(resource.provider.get(:ensure)).to eq(:present)
      expect(resource.provider.get(:options)).to eq([{ 'name' => 'routers', 'data' => '10.0.0.1' }])
    end

    it 'does not set provider when server config is absent' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)
      original_provider = resource.provider
      resources = { 'dhcp4' => resource }

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

    it 'returns true when interfaces-config key exists' do
      expect(provider_class.present?({ 'interfaces-config' => { 'interfaces' => ['*'] } })).to be true
    end

    it 'returns true when hosts-database key exists' do
      expect(provider_class.present?({ 'hosts-database' => {} })).to be true
    end

    it 'returns false when no server keys exist' do
      expect(provider_class.present?({ 'subnet4' => [] })).to be false
    end

    it 'returns false for empty hash' do
      expect(provider_class.present?({})).to be false
    end
  end

  describe 'property accessors' do
    let(:provider) do
      provider_class.new(
        ensure: :present,
        name: 'dhcp4',
        options: [{ 'name' => 'routers', 'data' => '10.0.0.1' }],
        hooks_libraries: [{ 'library' => '/path/to/lib.so' }],
        lease_database: lease_db,
      )
    end

    it 'returns options from property_hash' do
      expect(provider.options).to eq([{ 'name' => 'routers', 'data' => '10.0.0.1' }])
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
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(name: 'dhcp4', config_path: config_path, lease_database: lease_db)
      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      original_content = File.read(config_path)
      provider.flush

      expect(File.read(config_path)).to eq(original_content)
    end
  end

  context 'when transitioning from inline to host-database reservations' do
    let(:sensitive_host_password) { Puppet::Pops::Types::PSensitiveType::Sensitive.new('host_password') }

    it 'removes inline reservations from all subnets when host_database is configured' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                { 'hw-address' => 'aa:bb:cc:dd:ee:ff', 'ip-address' => '192.0.2.50' },
                { 'hw-address' => '11:22:33:44:55:66', 'ip-address' => '192.0.2.51' },
              ],
            },
            {
              'id' => 2,
              'subnet' => '10.0.0.0/24',
              'reservations' => [
                { 'hw-address' => 'aa:aa:aa:aa:aa:aa', 'ip-address' => '10.0.0.50' },
              ],
            },
          ],
        },
      )

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db.merge('password' => sensitive_password),
        host_database: host_db.merge('password' => sensitive_host_password),
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      expect(Puppet).to receive(:warning).with(%r{removed 3 inline reservation\(s\)})

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      subnets = config.dig('Dhcp4', 'subnet4')

      expect(Array(subnets.find { |s| s['id'] == 1 }['reservations'])).to be_empty
      expect(Array(subnets.find { |s| s['id'] == 2 }['reservations'])).to be_empty
      expect(config.dig('Dhcp4', 'hosts-database')).not_to be_nil
    end

    it 'preserves inline reservations when host_database is not configured' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            {
              'id' => 1,
              'subnet' => '192.0.2.0/24',
              'reservations' => [
                { 'hw-address' => 'aa:bb:cc:dd:ee:ff', 'ip-address' => '192.0.2.50' },
              ],
            },
          ],
        },
      )

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db.merge('password' => sensitive_password),
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      expect(Puppet).not_to receive(:warning)

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      reservations = config.dig('Dhcp4', 'subnet4', 0, 'reservations')

      expect(reservations).not_to be_nil
      expect(reservations.size).to eq(1)
      expect(reservations.first['hw-address']).to eq('aa:bb:cc:dd:ee:ff')
    end

    it 'emits no warning when host_database is set but no inline reservations exist' do
      write_config(
        config_path,
        'Dhcp4' => {
          'subnet4' => [
            { 'id' => 1, 'subnet' => '192.0.2.0/24' },
          ],
        },
      )

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db.merge('password' => sensitive_password),
        host_database: host_db.merge('password' => sensitive_host_password),
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      expect(Puppet).not_to receive(:warning)

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config.dig('Dhcp4', 'hosts-database')).not_to be_nil
    end
  end

  context 'when creating server configuration with ddns_qualifying_suffix' do
    it 'writes ddns-qualifying-suffix to the config file' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        ddns_qualifying_suffix: 'example.org',
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config.dig('Dhcp4', 'ddns-qualifying-suffix')).to eq('example.org')
    end

    it 'omits ddns-qualifying-suffix when not provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('ddns-qualifying-suffix')
    end
  end

  context 'when creating server configuration with ddns_update_on_renew' do
    it 'writes ddns-update-on-renew true to the config file' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
        ddns_update_on_renew: true,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config.dig('Dhcp4', 'ddns-update-on-renew')).to be(true)
    end

    it 'omits ddns-update-on-renew when not provided' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      resource = type_class.new(
        name: 'dhcp4',
        config_path: config_path,
        lease_database: lease_db,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.commit_all!

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('ddns-update-on-renew')
    end
  end
end
