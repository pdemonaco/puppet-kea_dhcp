# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/util/execution'

provider_class = Puppet::Type.type(:kea_dhcp_v4_commit).provider(:json)

describe provider_class do
  let(:type_class) { Puppet::Type.type(:kea_dhcp_v4_commit) }
  let(:tempfile) { Tempfile.new('kea-dhcp4') }
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
      scope_provider_class = Puppet::Type.type(:kea_dhcp_v4_scope).provider(:json)
      scope_provider_class.mark_dirty(config_path)

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      expect(provider.applied).to eq('pending')
    end
  end

  describe '#flush' do
    it 'commits dirty paths to disk' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      scope_type = Puppet::Type.type(:kea_dhcp_v4_scope)
      scope_provider_class = scope_type.provider(:json)

      # Simulate scope flush by modifying the shared cache and marking dirty
      config = provider_class.config_for(config_path)
      config['Dhcp4']['subnet4'] << { 'id' => 1, 'subnet' => '192.0.2.0/24' }
      scope_provider_class.mark_dirty(config_path)

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      provider.flush

      written = JSON.parse(File.read(config_path))
      expect(written['Dhcp4']['subnet4'].first['subnet']).to eq('192.0.2.0/24')
    end

    it 'is a no-op when dirty_paths is empty' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })
      original = File.read(config_path)

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      provider.flush

      expect(File.read(config_path)).to eq(original)
    end

    it 'removes the temp directory after a successful commit' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      scope_provider_class = Puppet::Type.type(:kea_dhcp_v4_scope).provider(:json)
      config = provider_class.config_for(config_path)
      config['Dhcp4']['subnet4'] << { 'id' => 1, 'subnet' => '192.0.2.0/24' }
      scope_provider_class.mark_dirty(config_path)

      captured_dir = nil
      allow(Dir).to receive(:mktmpdir).and_wrap_original do |orig, *args|
        dir = orig.call(*args)
        captured_dir = dir
        dir
      end

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      provider.flush

      expect(Dir.exist?(captured_dir)).to be false
    end

    it 'removes the temp directory after a failed validation' do
      write_config(config_path, 'Dhcp4' => { 'subnet4' => [] })

      scope_provider_class = Puppet::Type.type(:kea_dhcp_v4_scope).provider(:json)
      scope_provider_class.mark_dirty(config_path)

      failing_result = double('execution_result', exitstatus: 1, to_s: '')
      allow(Puppet::Util::Execution).to receive(:execute).and_return(failing_result)

      captured_dir = nil
      allow(Dir).to receive(:mktmpdir).and_wrap_original do |orig, *args|
        dir = orig.call(*args)
        captured_dir = dir
        dir
      end

      resource = type_class.new(name: config_path)
      provider = provider_class.new
      provider.resource = resource

      expect { provider.flush }.to raise_error(Puppet::Error)

      expect(Dir.exist?(captured_dir)).to be false
    end
  end
end
