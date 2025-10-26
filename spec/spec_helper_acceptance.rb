# frozen_string_literal: true

require 'puppet_litmus'
require 'yaml'
require_relative 'spec_helper_acceptance_local' if File.exist?(File.join(__dir__, 'spec_helper_acceptance_local.rb'))

PuppetLitmus.configure!

module AcceptanceSuiteSetup
  extend self
  extend PuppetLitmus

  def prepare!
    configure_target_host!
    ensure_puppet_agent_present
  end

  def ensure_puppet_agent_present
    commands = [
      'PATH=/opt/puppetlabs/puppet/bin:$PATH puppet --version',
      '/opt/puppetlabs/puppet/bin/puppet --version'
    ]

    commands.each do |cmd|
      result = run_shell_on_target(cmd, expect_failures: true)
      return if result.exit_code.zero?
    end

    raise('Puppet agent must be installed on the target host before running acceptance tests.')
  end

  private

  def run_shell_on_target(command, **opts)
    targets_option = opts.delete(:targets)
    selected_targets = targets_option || target_nodes
    run_shell(command, opts.merge(targets: selected_targets))
  end

  def target_nodes
    target = ENV['TARGET_HOST']
    inventory_list = inventory_targets

    return target if target && !target.empty? && inventory_list.include?(target)

    inventory_list
  end

  def inventory_targets
    inventory = if File.exist?('spec/fixtures/litmus_inventory.yaml')
                  YAML.safe_load(File.read('spec/fixtures/litmus_inventory.yaml'))
                else
                  {}
                end
    groups = Array(inventory['groups'])
    targets = groups.flat_map { |group| Array(group['targets']) }
    uris = targets.map { |t| t['uri'] || t['name'] }.compact
    raise('No targets found in spec/fixtures/litmus_inventory.yaml and TARGET_HOST is not set.') if uris.empty?

    uris
  end

  def configure_target_host!
    return unless ENV['TARGET_HOST'].nil? || ENV['TARGET_HOST'].empty?

    ENV['TARGET_HOST'] = inventory_targets.first
  end
end

RSpec.configure do |config|
  config.before :suite do
    AcceptanceSuiteSetup.prepare!
  end
end
