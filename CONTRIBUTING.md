# Contributing

Thanks for spending time improving this module! The checks in `.github/workflows/pdk.yml` run automatically in GitHub Actions, and you can reproduce them locally before pushing a change.

## Prerequisites

- [Puppet Development Kit (PDK)](https://www.puppet.com/docs/pdk/latest/pdk.html)
- Docker (for acceptance tests)

## Test Workflow

### Install dependencies

```bash
pdk bundle install
```

### Syntax validation

Validates Puppet syntax, metadata, and runs linting:

```bash
pdk validate
```

### Unit tests

Run all unit tests (rspec-puppet):

```bash
pdk test unit
```

Run a single unit test file:

```bash
pdk test unit --tests=spec/classes/kea_dhcp_spec.rb
```

### Acceptance tests

The acceptance suite uses [puppet-litmus](https://github.com/puppetlabs/puppet_litmus) with Docker-backed test nodes. You will need a working Docker installation.

1. Provision the test environment (Rocky Linux 9 container):

   ```bash
   pdk bundle exec rake 'litmus:provision_list[default]'
   ```

2. Install the Puppet agent on the test node:

   ```bash
   pdk bundle exec rake litmus:install_agent
   ```

3. Install the module and its dependencies:

   ```bash
   pdk bundle exec rake litmus:install_module
   ```

4. Run all acceptance tests:

   ```bash
   pdk bundle exec rake litmus:acceptance:parallel
   ```

5. When you are done, tear down the environment to reclaim resources:

   ```bash
   pdk bundle exec rake litmus:tear_down
   ```

### Quick acceptance test cycle

After the initial provisioning, you can iterate on acceptance tests by reinstalling the module and re-running tests:

```bash
pdk bundle exec rake litmus:install_module
pdk bundle exec rake litmus:acceptance:parallel
```

The GitHub Action automatically skips the acceptance stage if the `spec/acceptance` directory has no test files. Once acceptance coverage is added, the workflow will execute the same commands listed above.
