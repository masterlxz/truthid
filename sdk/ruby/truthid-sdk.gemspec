Gem::Specification.new do |spec|
  spec.name        = "truthid-sdk"
  spec.version     = "0.1.0"
  spec.summary     = "TruthID authentication SDK for Ruby"
  spec.description = "TruthID passwordless, decentralized authentication SDK for Ruby. " \
                      "No TruthID-operated server, no passwords, no third-party login."
  spec.authors     = ["masterlxz"]
  spec.license     = "MIT"
  spec.homepage    = "https://github.com/masterlxz/truthid/tree/main/sdk/ruby#readme"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/masterlxz/truthid",
    "bug_tracker_uri" => "https://github.com/masterlxz/truthid/issues",
  }
  spec.require_paths = ["lib"]
  spec.files       = Dir["lib/**/*"] + ["README.md", "LICENSE"]
  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "eth", "~> 0.5"
end
