# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'json'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_ddns_server).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_ddns_server) }
  let(:tempfile) { Tempfile.new('kea-ddns-server') }
  let(:config_path) { tempfile.path }

  before(:each) do
    tempfile.close
    provider_class.clear_state!
    execution_result = double('execution_result', exitstatus: 0)
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
    it 'writes basic server configuration' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })

      resource = type_class.new(
        name: 'dhcp-ddns',
        config_path: config_path,
        ip_address: '192.168.1.10',
        port: 53_001,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      ddns = config['DhcpDdns']

      expect(ddns['ip-address']).to eq('192.168.1.10')
      expect(ddns['port']).to eq(53_001)
    end

    it 'writes TSIG keys when provided' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })

      resource = type_class.new(
        name: 'dhcp-ddns',
        config_path: config_path,
        tsig_keys: [
          { 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'LSWXnfkKZjdPJI5QxlpnfQ==' },
          { 'name' => 'bar', 'algorithm' => 'HMAC-SHA256', 'secret' => 'bZEG7Ow8OgAUPfLWV3aAUQ==' },
        ],
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      ddns = config['DhcpDdns']

      expect(ddns['tsig-keys']).to contain_exactly(
        { 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'LSWXnfkKZjdPJI5QxlpnfQ==' },
        { 'name' => 'bar', 'algorithm' => 'HMAC-SHA256', 'secret' => 'bZEG7Ow8OgAUPfLWV3aAUQ==' },
      )
    end

    it 'creates default structure when file does not exist' do
      File.delete(config_path) if File.exist?(config_path)

      resource = type_class.new(
        name: 'dhcp-ddns',
        config_path: config_path,
        ip_address: '127.0.0.1',
        port: 53_001,
      )

      provider = provider_class.new
      provider.resource = resource
      resource.provider = provider

      provider.create
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)

      expect(config).to have_key('DhcpDdns')
      expect(config['DhcpDdns']).to have_key('forward-ddns')
      expect(config['DhcpDdns']).to have_key('reverse-ddns')
    end
  end

  context 'when updating server configuration' do
    it 'modifies existing configuration' do
      write_config(
        config_path,
        'DhcpDdns' => {
          'ip-address' => '127.0.0.1',
          'port' => 53_001,
          'forward-ddns' => {},
          'reverse-ddns' => {},
        },
      )

      resource = type_class.new(
        name: 'dhcp-ddns',
        config_path: config_path,
        ip_address: '192.168.1.20',
        port: 8080,
      )

      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource)

      provider = provider_class.new(provider_class.resource_hash(
                                      { 'ip-address' => '127.0.0.1', 'port' => 53_001 },
                                      config_path,
                                    ))
      provider.resource = resource
      resource.provider = provider

      provider.ip_address = '192.168.1.20'
      provider.port = 8080
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      ddns = config['DhcpDdns']

      expect(ddns['ip-address']).to eq('192.168.1.20')
      expect(ddns['port']).to eq(8080)
    end

    it 'adds TSIG keys to existing configuration' do
      write_config(
        config_path,
        'DhcpDdns' => {
          'ip-address' => '127.0.0.1',
          'port' => 53_001,
          'forward-ddns' => {},
          'reverse-ddns' => {},
        },
      )

      resource = type_class.new(
        name: 'dhcp-ddns',
        config_path: config_path,
        tsig_keys: [{ 'name' => 'new-key', 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc123==' }],
      )

      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource)

      provider = provider_class.new(provider_class.resource_hash(
                                      { 'ip-address' => '127.0.0.1', 'port' => 53_001 },
                                      config_path,
                                    ))
      provider.resource = resource
      resource.provider = provider

      provider.tsig_keys = [{ 'name' => 'new-key', 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc123==' }]
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      ddns = config['DhcpDdns']

      expect(ddns['tsig-keys']).to contain_exactly(
        { 'name' => 'new-key', 'algorithm' => 'HMAC-SHA256', 'secret' => 'abc123==' },
      )
    end
  end

  context 'when destroying server configuration' do
    it 'removes server configuration keys' do
      write_config(
        config_path,
        'DhcpDdns' => {
          'ip-address' => '127.0.0.1',
          'port' => 53_001,
          'tsig-keys' => [{ 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'abc==' }],
          'forward-ddns' => {},
          'reverse-ddns' => {},
        },
      )

      resource = type_class.new(
        name: 'dhcp-ddns',
        config_path: config_path,
        ensure: :absent,
      )

      catalog = Puppet::Resource::Catalog.new
      catalog.add_resource(resource)

      provider = provider_class.new(provider_class.resource_hash(
                                      {
                                        'ip-address' => '127.0.0.1',
                                        'port' => 53_001,
                                        'tsig-keys' => [{ 'name' => 'foo', 'algorithm' => 'HMAC-MD5', 'secret' => 'abc==' }],
                                      },
                                      config_path,
                                    ))
      provider.resource = resource
      resource.provider = provider

      provider.destroy
      provider.flush
      provider_class.post_resource_eval

      config = read_config(config_path)
      ddns = config['DhcpDdns']

      expect(ddns).not_to have_key('ip-address')
      expect(ddns).not_to have_key('port')
      expect(ddns).not_to have_key('tsig-keys')
      expect(ddns).to have_key('forward-ddns')
      expect(ddns).to have_key('reverse-ddns')
    end
  end

  context 'when discovering existing configuration' do
    it 'returns server instance when configuration exists' do
      config = {
        'DhcpDdns' => {
          'ip-address' => '192.168.1.10',
          'port' => 8080,
          'forward-ddns' => {},
          'reverse-ddns' => {},
        },
      }

      allow(provider_class).to receive(:config_for).and_return(config)

      instances = provider_class.instances

      expect(instances.length).to eq(1)
      expect(instances[0].get(:name)).to eq('dhcp-ddns')
      expect(instances[0].get(:ip_address)).to eq('192.168.1.10')
      expect(instances[0].get(:port)).to eq(8080)
    end

    it 'returns empty array when no configuration exists' do
      config = { 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} } }

      allow(provider_class).to receive(:config_for).and_return(config)

      instances = provider_class.instances

      expect(instances).to be_empty
    end
  end
end
