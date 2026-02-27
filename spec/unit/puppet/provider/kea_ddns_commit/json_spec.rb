# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_ddns_commit).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_ddns_commit) }
  let(:tempfile) { Tempfile.new('kea-ddns') }
  let(:config_path) { tempfile.path }

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

  describe '#applied' do
    it 'returns committed when no dirty paths exist' do
      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      expect(provider.applied).to eq('committed')
    end

    it 'returns pending when dirty paths exist' do
      domain_provider_class = Puppet::Type.type(:kea_ddns_domain).provider(:json)
      domain_provider_class.mark_dirty(config_path)

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      expect(provider.applied).to eq('pending')
    end
  end

  describe '#flush' do
    it 'commits dirty paths to disk' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })

      domain_provider_class = Puppet::Type.type(:kea_ddns_domain).provider(:json)

      # Simulate domain flush by modifying the shared cache and marking dirty
      config = provider_class.config_for(config_path)
      config['DhcpDdns']['forward-ddns']['ddns-domains'] = [{ 'name' => 'example.com.' }]
      domain_provider_class.mark_dirty(config_path)

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      provider.flush

      written = JSON.parse(File.read(config_path))
      expect(written['DhcpDdns']['forward-ddns']['ddns-domains'].first['name']).to eq('example.com.')
    end

    it 'is a no-op when dirty_paths is empty' do
      write_config(config_path, 'DhcpDdns' => { 'forward-ddns' => {}, 'reverse-ddns' => {} })
      original = File.read(config_path)

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      provider.flush

      expect(File.read(config_path)).to eq(original)
    end
  end
end
