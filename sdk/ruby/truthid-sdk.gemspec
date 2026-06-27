Gem::Specification.new do |spec|
  spec.name        = "truthid-sdk"
  spec.version     = "0.1.0"
  spec.summary     = "TruthID authentication SDK for Ruby"
  spec.require_paths = ["lib"]
  spec.files       = Dir["lib/**/*"]
  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "eth", "~> 0.5"
end
