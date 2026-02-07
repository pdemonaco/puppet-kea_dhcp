# Contributing

Thanks for spending time improving this module! The checks in `.github/workflows/20-pdk.yml` run automatically in GitHub Actions, and you can reproduce them locally before pushing a change.

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

1. Provision the test environment (Rocky Linux 8 and 9 containers):

   ```bash
   pdk bundle exec rake 'litmus:provision_list[default]'
   ```

2. Install the Puppet agent on all test nodes:

   ```bash
   pdk bundle exec rake litmus:install_agent
   ```

3. Install the module and its dependencies on all nodes:

   ```bash
   pdk bundle exec rake litmus:install_module
   ```

4. Run all acceptance tests on all nodes:

   ```bash
   pdk bundle exec rake litmus:acceptance:parallel
   ```

5. Determine the names of the nodes in the litmus inventory file

   ```bash
   HOSTS=$(yq '(.groups[] | .targets[] | .alias )' spec/fixtures/litmus_inventory.yaml)
   ```

6. Run a specific test file on a specific node

   ```bash
   TEST=spec/acceptance/kea_dhcp_spec.rb
   TARGET_NODE='localhost:52963' pdk bundle exec rspec "${TEST}"
   ```

7. When you are done, tear down the environment to reclaim resources:

   ```bash
   pdk bundle exec rake litmus:tear_down
   ```

### Quick acceptance test cycles

#### Full Test Suite

After the initial provisioning, you can iterate on all acceptance tests by reinstalling the module and re-running tests:

```bash
pdk bundle exec rake litmus:install_module
pdk bundle exec rake litmus:acceptance:parallel
```

#### Single Test File

When developing or troubleshooting a test you can target your execution to a specific test file to speed up troublshooting.

```bash
TEST=./spec/acceptance/kea_dhcp_spec.rb
HOSTS=$(yq '(.groups[] | .targets[] | .alias )' spec/fixtures/litmus_inventory.yaml)
pdk bundle exec rake litmus:install_module
for H in $HOSTS; do TARGET_HOST="${H}" pdk bundle exec rspec "${TEST}"; done
```
