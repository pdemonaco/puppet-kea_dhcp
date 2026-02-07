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
    @config_cache ||= {}
  end

  def self.dirty_paths
    @dirty_paths ||= Set.new
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
        'forward-ddns' => {},
        'reverse-ddns' => {},
      },
    }
  end

  def self.mark_dirty(path)
    dirty_paths.add(path)
  end

  def self.clear_state!
    config_cache.clear
    dirty_paths.clear
    temp_configs.clear
    @server_config_path = nil
    @commit_controllers = Set.new
    staged_paths.clear
  end

  def self.commit_controllers
    @commit_controllers ||= Set.new
  end

  def self.register_commit_controller(path)
    commit_controllers.add(path)
  end

  def self.unregister_commit_controller(path)
    commit_controllers.delete(path)
  end

  class << self
    attr_accessor :server_config_path
  end

  def self.save_if_dirty(path, commit: false)
    return unless dirty_paths.include?(path)

    stage_config(path)
    commit!(path) if commit
  end

  def self.commit!(path)
    return unless dirty_paths.include?(path)

    stage_config(path) unless staged_paths.include?(path)
    temp = temp_configs[path]

    Puppet::Util::Execution.execute(['kea-dhcp-ddns', '-t', temp.temp_path], failonfail: true)

    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.mv(temp.temp_path, path, force: true)

    dirty_paths.delete(path)
  ensure
    cleanup_temp_config(path)
  end

  def self.commit_all!
    dirty_paths.to_a.each { |path| commit!(path) }
  end

  def self.commit_uncontrolled!
    (dirty_paths - commit_controllers).to_a.each { |path| commit!(path) }
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
    @temp_configs ||= {}
  end

  def self.staged_paths
    @staged_paths ||= Set.new
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
end
