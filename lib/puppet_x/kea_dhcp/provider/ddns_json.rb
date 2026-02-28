# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'fileutils'
require 'set'
require 'puppet/util/execution'

# rubocop:disable Style/Documentation
module PuppetX; end unless defined?(PuppetX)
module PuppetX::KeaDhcp; end unless defined?(PuppetX::KeaDhcp)
module PuppetX::KeaDhcp::Provider; end unless defined?(PuppetX::KeaDhcp::Provider)
# rubocop:enable Style/Documentation

# Provides shared helpers for Kea DHCP-DDNS JSON-backed providers.
class PuppetX::KeaDhcp::Provider::DdnsJson < Puppet::Provider
  # Manages staged configuration written to a temporary location
  class TempConfig
    attr_reader :dir, :temp_path

    def initialize(target_path)
      @dir = Dir.mktmpdir('kea-ddns')
      @temp_path = File.join(@dir, File.basename(target_path))
    end

    def write(config)
      File.write(temp_path, JSON.pretty_generate(config) + "\n")
    end

    def cleanup
      FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
    end
  end

  DEFAULT_CONFIG_PATH = '/etc/kea/kea-dhcp-ddns.conf'
  DDNS_KEY = 'DhcpDdns'
  USER_CONTEXT_KEY = 'user-context'
  PUPPET_NAME_KEY = 'puppet_name'

  def self.config_cache
    # All DDNS provider classes share one cache so cross-provider changes
    # (e.g. kea_ddns_server + kea_ddns_domain) are committed together.
    root = PuppetX::KeaDhcp::Provider::DdnsJson
    root.instance_variable_get(:@config_cache) ||
      root.instance_variable_set(:@config_cache, {})
  end

  # dirty_paths, staged_paths, and temp_configs are pinned to the base class so
  # that all provider subclasses (server, domain, commit) share a single
  # tracking set. This allows the commit provider to see every path dirtied by
  # any sibling provider.
  def self.dirty_paths
    root = PuppetX::KeaDhcp::Provider::DdnsJson
    root.instance_variable_get(:@dirty_paths) ||
      root.instance_variable_set(:@dirty_paths, Set.new)
  end

  def self.config_for(path)
    config_cache[path] ||= load_config(path)
  end

  def self.load_config(path)
    contents = begin
                 File.read(path)
               rescue Errno::ENOENT
                 return default_config
               end

    JSON.parse(contents)
  rescue JSON::ParserError => e
    raise Puppet::Error, "Failed to parse #{path}: #{e.message}"
  end

  def self.default_config
    {
      DDNS_KEY => {
        'ip-address' => '127.0.0.1',
        'port' => 53001,
        'forward-ddns' => {
          'ddns-domains' => [],
        },
        'reverse-ddns' => {
          'ddns-domains' => [],
        },
      },
    }
  end

  def self.mark_dirty(path)
    dirty_paths.add(path)
  end

  def self.clear_state!
    cleanup_temp_configs
    config_cache.clear
    root = PuppetX::KeaDhcp::Provider::DdnsJson
    root.instance_variable_set(:@dirty_paths, Set.new)
    root.instance_variable_set(:@staged_paths, Set.new)
    root.instance_variable_set(:@temp_configs, {})
    @server_config_path = nil
  end

  class << self
    attr_accessor :server_config_path
  end

  def self.save_if_dirty(path, commit: false)
    return unless dirty_paths.include?(path)

    stage_config(path)
    commit!(path) if commit
  end

  def self.redact_config(config)
    config = config.dup
    ddns = config[DDNS_KEY]
    return config unless ddns && ddns['tsig-keys']

    ddns = ddns.dup
    ddns['tsig-keys'] = ddns['tsig-keys'].map do |key|
      key = key.dup
      key['secret'] = '[REDACTED]' if key.key?('secret')
      key
    end
    config[DDNS_KEY] = ddns
    config
  end

  def self.commit!(path)
    return unless dirty_paths.include?(path)

    stage_config(path) unless staged_paths.include?(path)
    temp = temp_configs[path]

    Puppet.debug { "kea-dhcp-ddns committing config to #{path}:\n#{JSON.pretty_generate(redact_config(config_for(path)))}" }

    # Run validation
    result = Puppet::Util::Execution.execute(['kea-dhcp-ddns', '-t', temp.temp_path], failonfail: false, combine: true)

    unless result.exitstatus.zero?
      result.to_s.each_line { |line| Puppet.err(line.chomp) if line.include?(' ERROR ') }
      raise Puppet::Error, "kea-dhcp-ddns validation failed for #{path}"
    end

    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.mv(temp.temp_path, path, force: true)

    dirty_paths.delete(path)
  ensure
    cleanup_temp_config(path)
  end

  def self.commit_all!
    dirty_paths.to_a.each { |path| commit!(path) }
  ensure
    cleanup_temp_configs
  end

  def self.stringify_keys(hash)
    return {} unless hash.respond_to?(:each)

    hash.each_with_object({}) do |(key, val), acc|
      acc[key.to_s] = unwrap_sensitive(val)
    end
  end

  def self.unwrap_sensitive(value)
    if value.respond_to?(:unwrap)
      value.unwrap
    else
      value
    end
  end

  def self.temp_configs
    root = PuppetX::KeaDhcp::Provider::DdnsJson
    root.instance_variable_get(:@temp_configs) ||
      root.instance_variable_set(:@temp_configs, {})
  end

  def self.staged_paths
    root = PuppetX::KeaDhcp::Provider::DdnsJson
    root.instance_variable_get(:@staged_paths) ||
      root.instance_variable_set(:@staged_paths, Set.new)
  end

  def self.stage_config(path)
    config = config_for(path)
    temp = temp_configs[path] ||= TempConfig.new(path)
    temp.write(config)
    staged_paths.add(path)
  end

  def self.cleanup_temp_config(path)
    temp = temp_configs.delete(path)
    temp&.cleanup
    staged_paths.delete(path)
  end

  def self.cleanup_temp_configs
    temp_configs.each_key { |path| cleanup_temp_config(path) }
  end

  private_class_method :temp_configs, :staged_paths, :stage_config,
                        :cleanup_temp_config, :cleanup_temp_configs
end
