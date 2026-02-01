# frozen_string_literal: true

require 'bundler'
require 'puppet_litmus/rake_tasks' if Gem.loaded_specs.key? 'puppet_litmus'
require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-syntax/tasks/puppet-syntax'
require 'puppet-strings/tasks' if Gem.loaded_specs.key? 'puppet-strings'

PuppetLint.configuration.send('disable_relative')
PuppetLint.configuration.send('disable_80chars')
PuppetLint.configuration.send('disable_140chars')
PuppetLint.configuration.send('disable_class_inherits_from_params_class')
PuppetLint.configuration.send('disable_autoloader_layout')
PuppetLint.configuration.send('disable_documentation')
PuppetLint.configuration.send('disable_single_quote_string_with_variables')
PuppetLint.configuration.fail_on_warnings = true
PuppetLint.configuration.ignore_paths = [".vendor/**/*.pp", ".bundle/**/*.pp", "pkg/**/*.pp", "spec/**/*.pp", "tests/**/*.pp", "types/**/*.pp", "vendor/**/*.pp"]

require 'json'
require 'github_changelog_generator/task' if Gem.loaded_specs.key?('github_changelog_generator')

def changelog_user
  return unless Rake.application.top_level_tasks.include?('changelog')
  value = nil
  value ||= begin
    metadata_source = JSON.parse(File.read('metadata.json'))['source']
    metadata_match = metadata_source && metadata_source.match(%r{github\.com[:/]+([^/]+)/})
    metadata_match && metadata_match[1]
  end
  raise 'unable to find the changelog_user in metadata.json' if value.nil?
  puts "GitHubChangelogGenerator user:#{value}"
  value
end

def changelog_project
  return unless Rake.application.top_level_tasks.include?('changelog')

  value = nil
  value ||= begin
    metadata_source = JSON.parse(File.read('metadata.json'))['source']
    metadata_source_match = metadata_source && metadata_source.match(%r{github\.com[:/]+[^/]+/([^/.]+?)(?:\.git)?(?:[\/#?].*)?\z})
    metadata_source_match && metadata_source_match[1]
  end

  raise 'unable to find the changelog_project in metadata.json' if value.nil?

  puts "GitHubChangelogGenerator project:#{value}"
  value
end

def changelog_future_release
  return unless Rake.application.top_level_tasks.include?('changelog')
  value = format('v%s', JSON.parse(File.read('metadata.json'))['version'])
  raise 'unable to find the future_release (version) in metadata.json' if value.nil?
  puts "GitHubChangelogGenerator future_release:#{value}"
  value
end

if Gem.loaded_specs.key?('github_changelog_generator')
  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    raise "Set CHANGELOG_GITHUB_TOKEN environment variable eg 'export CHANGELOG_GITHUB_TOKEN=valid_token_here'" if Rake.application.top_level_tasks.include?('changelog') && ENV['CHANGELOG_GITHUB_TOKEN'].nil?
    config.user = changelog_user.to_s
    config.project = changelog_project.to_s
    config.future_release = changelog_future_release.to_s
    config.exclude_labels = ['maintenance']
    config.header = "# Change log\n\nAll notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org)."
    config.add_pr_wo_labels = true
    config.issues = false
    config.merge_prefix = "### UNCATEGORIZED PRS; LABEL THEM ON GITHUB"
    config.configure_sections = {
      "Changed" => {
        "prefix" => "### Changed",
        "labels" => ["backwards-incompatible"],
      },
      "Added" => {
        "prefix" => "### Added",
        "labels" => ["enhancement", "feature"],
      },
      "Fixed" => {
        "prefix" => "### Fixed",
        "labels" => ["bug", "documentation", "bugfix"],
      },
    }
  end
else
  desc 'Generate a Changelog from GitHub'
  task :changelog do
    raise <<~EOM
      The changelog tasks depends on recent features of the github_changelog_generator gem.
      Please manually add it to your .sync.yml for now, and run `pdk update`:
      ---
      Gemfile:
        optional:
          ':development':
            - gem: 'github_changelog_generator'
              version: '~> 1.15'
              condition: "Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new('2.3.0')"
    EOM
  end
end

