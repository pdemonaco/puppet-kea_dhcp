# frozen_string_literal: true

# node_encrypt requires SSL certificates to encrypt data, which are not present
# during unit testing. Require the library early and stub the encrypt/decrypt
# methods so that unit tests can compile catalogs that include node_encrypt
# functions without needing a live Puppet SSL infrastructure.
RSpec.configure do |c|
  c.before(:suite) do
    node_encrypt_lib = File.join(File.dirname(__FILE__), 'fixtures', 'modules', 'node_encrypt',
                                 'lib', 'puppet_x', 'node_encrypt')
    require node_encrypt_lib if File.exist?("#{node_encrypt_lib}.rb")
  end

  c.before(:each) do
    next unless defined?(PuppetX::NodeEncrypt)

    allow(PuppetX::NodeEncrypt).to receive(:encrypt).and_return(
      "-----BEGIN PKCS7-----\nFAKEENCRYPTED\n-----END PKCS7-----",
    )
    allow(PuppetX::NodeEncrypt).to receive(:decrypt).and_return('FAKE_DECRYPTED')
  end
end
