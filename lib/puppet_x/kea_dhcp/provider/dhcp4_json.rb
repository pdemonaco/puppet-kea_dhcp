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

# Provides shared helpers for Kea DHCPv4 JSON-backed providers.
class PuppetX::KeaDhcp::Provider::Dhcp4Json < Puppet::Provider
  # Manages staged configuration written to a temporary location
  class TempConfig
    attr_reader :dir, :temp_path

    def initialize(target_path)
      @dir = Dir.mktmpdir('kea-dhcp4')
      @temp_path = File.join(@dir, File.basename(target_path))
    end

    def write(config)
      File.write(temp_path, JSON.pretty_generate(config) + "\n")
    end

    def cleanup
      FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
    end
  end

  DEFAULT_CONFIG_PATH = '/etc/kea/kea-dhcp4.conf'
  DHCP4_KEY = 'Dhcp4'
  SUBNET4_KEY = 'subnet4'
  OPTION_DATA_KEY = 'option-data'
  LEASE_DATABASE_KEY = 'lease-database'
  HOOKS_LIBRARIES_KEY = 'hooks-libraries'
  USER_CONTEXT_KEY = 'puppet_name'
  SERVER_INSTANCE_NAME = 'dhcp4'

  def self.config_cache
    # All DHCPv4 provider classes share one cache so cross-provider changes
    # (e.g. kea_dhcp_v4_server + kea_dhcp_v4_scope) are committed together.
    root = PuppetX::KeaDhcp::Provider::Dhcp4Json
    root.instance_variable_get(:@config_cache) ||
      root.instance_variable_set(:@config_cache, {})
  end

  # dirty_paths, staged_paths, and temp_configs are pinned to the base class so
  # that all provider subclasses (server, scope, reservation, commit) share a
  # single tracking set. This allows the commit provider to see every path
  # dirtied by any sibling provider.
  def self.dirty_paths
    root = PuppetX::KeaDhcp::Provider::Dhcp4Json
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
      DHCP4_KEY => {
        SUBNET4_KEY => [],
      },
    }
  end

  def self.mark_dirty(path)
    dirty_paths.add(path)
  end

  def self.clear_state!
    cleanup_temp_configs
    config_cache.clear
    root = PuppetX::KeaDhcp::Provider::Dhcp4Json
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
    dhcp4 = config[DHCP4_KEY]
    return config unless dhcp4 && dhcp4[LEASE_DATABASE_KEY]

    dhcp4 = dhcp4.dup
    db = dhcp4[LEASE_DATABASE_KEY].dup
    db['password'] = '[REDACTED]' if db.key?('password')
    dhcp4[LEASE_DATABASE_KEY] = db
    config[DHCP4_KEY] = dhcp4
    config
  end

  def self.commit!(path)
    return unless dirty_paths.include?(path)

    stage_config(path) unless staged_paths.include?(path)
    temp = temp_configs[path]

    Puppet.debug { "kea-dhcp4 committing config to #{path}:\n#{JSON.pretty_generate(redact_config(config_for(path)))}" }

    result = Puppet::Util::Execution.execute(['kea-dhcp4', '-t', temp.temp_path], failonfail: false, combine: true)

    unless result.exitstatus.zero?
      result.to_s.each_line { |line| Puppet.err(line.chomp) if line.include?(' ERROR ') }
      raise Puppet::Error, "kea-dhcp4 validation failed for #{path}"
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

  def stringify_keys(hash)
    self.class.stringify_keys(hash)
  end

  def unwrap_sensitive(value)
    self.class.unwrap_sensitive(value)
  end

  def config_path
    path = resource[:config_path]
    if path && (resource_config_path_specified? || path != DEFAULT_CONFIG_PATH)
      return path
    end

    path = self.class.server_config_path
    return path if path

    server_resource = server_resource_from_catalog
    if server_resource
      path = if server_resource.respond_to?(:[])
               server_resource[:config_path] || server_resource['config_path']
             end
      path ||= server_resource.to_hash[:config_path] if server_resource.respond_to?(:to_hash)
      path ||= server_resource.to_hash['config_path'] if server_resource.respond_to?(:to_hash)
      return path if path
    end

    DEFAULT_CONFIG_PATH
  end

  def self.temp_configs
    root = PuppetX::KeaDhcp::Provider::Dhcp4Json
    root.instance_variable_get(:@temp_configs) ||
      root.instance_variable_set(:@temp_configs, {})
  end

  def self.staged_paths
    root = PuppetX::KeaDhcp::Provider::Dhcp4Json
    root.instance_variable_get(:@staged_paths) ||
      root.instance_variable_set(:@staged_paths, Set.new)
  end

  def self.stage_config(path)
    temp = temp_config_for(path)
    temp.write(config_for(path))
    staged_paths.add(path)
    temp
  end

  def self.temp_config_for(path)
    temp_configs[path] ||= TempConfig.new(path)
  end

  def self.cleanup_temp_config(path)
    temp = temp_configs.delete(path)
    temp&.cleanup
    staged_paths.delete(path)
  end

  def self.cleanup_temp_configs
    temp_configs.each_key { |path| cleanup_temp_config(path) }
  end

  private_class_method :temp_configs, :staged_paths, :stage_config, :temp_config_for,
                        :cleanup_temp_config, :cleanup_temp_configs

  private

  def resource_config_path_specified?
    return false unless resource.respond_to?(:original_parameters)

    params = resource.original_parameters
    return false unless params.respond_to?(:key?)

    params.key?(:config_path) || params.key?('config_path')
  end

  def server_resource_from_catalog
    return unless resource.respond_to?(:catalog)
    return unless resource.catalog

    type_keys = [
      :kea_dhcp_v4_server,
      :Kea_dhcp_v4_server,
      'kea_dhcp_v4_server',
      'Kea_dhcp_v4_server',
    ]

    type_keys.each do |type_key|
      found = resource.catalog.resource(type_key, SERVER_INSTANCE_NAME)
      return found if found
    end

    resource.catalog.resources.find do |res|
      next unless res.type && res.title == SERVER_INSTANCE_NAME

      res.type.casecmp('Kea_dhcp_v4_server')&.zero?
    end
  rescue Puppet::Error
    nil
  end
end
