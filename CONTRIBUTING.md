# Contributing

Thanks for spending time improving this module! The checks in `.github/workflows/pdk.yml` run automatically in GitHub Actions, and you can reproduce them locally before pushing a change.

## Test Workflow

### Syntax validation
- `pdk validate`

### Unit tests
- `pdk test unit`

### Acceptance tests
The acceptance suite uses [puppet-litmus](https://github.com/puppetlabs/puppet_litmus) with Docker-backed test nodes. You will need a working Docker installation as well as Ruby and Bundler.

1. Install the Ruby dependencies (include the `system_tests` group):
   ```bash
   bundle config set path vendor/bundle
   BUNDLE_WITH=system_tests bundle install
   ```
2. Prepare module fixtures for the suite:
   ```bash
   bundle exec rake spec_prep
   ```
3. Run the acceptance tests. The task provisions the Docker containers declared in `provision.yaml` (Rocky Linux 9), installs the module, and executes every spec in `spec/acceptance`:
   ```bash
   LITMUS_BACKEND=docker bundle exec rake 'litmus:acceptance:parallel'
   ```
4. When you are done, tear the environment down to reclaim resources:
   ```bash
   LITMUS_BACKEND=docker bundle exec rake 'litmus:tear_down'
   ```

The GitHub Action automatically skips the acceptance stage if the `spec/acceptance` directory has no test files. Once acceptance coverage is added, the workflow will execute the same commands listed above.
