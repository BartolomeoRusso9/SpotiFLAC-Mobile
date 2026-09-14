Pod::Spec.new do |spec|
  spec.name = 'SpotiFLACBackend'
  spec.version = '0.1.0'
  spec.summary = 'Rust backend bindings for SpotiFLAC Mobile'
  spec.homepage = 'https://github.com/spotiflacapp/SpotiFLAC-Mobile'
  spec.license = { :type => 'MIT', :file => 'LICENSE' }
  spec.author = { 'SpotiFLAC Mobile' => 'noreply@spotiflac.local' }
  spec.source = { :path => '.' }
  spec.ios.deployment_target = '16.0'
  spec.swift_version = '5.0'
  spec.static_framework = true
  # build_rust_backend.sh stages this spec beside the generated iOS artifacts.
  spec.source_files = 'SpotiFLACBackend.swift'
  spec.vendored_frameworks = 'SpotiFLACBackendFFI.xcframework'
  spec.frameworks = 'Security', 'CoreFoundation'
end
