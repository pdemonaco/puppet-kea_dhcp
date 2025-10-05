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
      provider_class.post_resource_eval

      config = read_config(config_path)
      dhcp4 = config['Dhcp4']

      expect(dhcp4['lease-database']).to include('type' => 'postgresql', 'user' => 'kea', 'password' => 'kea_password')
      expect(dhcp4['lease-database']['port']).to eq(5433)
      expect(dhcp4['option-data']).to contain_exactly({ 'name' => 'routers', 'data' => '10.0.0.1' })
      expect(dhcp4['subnet4']).to eq([])
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
      provider_class.post_resource_eval

      config = read_config(config_path)
      dhcp4 = config['Dhcp4']

      expect(dhcp4['lease-database']['password']).to eq('new_secret')
      expect(dhcp4['option-data']).to contain_exactly({ 'name' => 'domain-name-servers', 'data' => '8.8.8.8' })
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
      provider_class.post_resource_eval

      config = read_config(config_path)
      expect(config['Dhcp4']).not_to have_key('lease-database')
      expect(config['Dhcp4']).not_to have_key('option-data')
    end
  end
end
