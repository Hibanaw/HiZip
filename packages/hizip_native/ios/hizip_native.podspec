#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint hizip_native.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'hizip_native'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  # Classes/Unrar contains forwarders for the upstream library units.
  s.source_files = 'Classes/**/*'
  s.resource_bundles = { 'hizip_native_licenses' => ['Resources/*.txt'] }
  s.libraries = 'archive', 'c++'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++11',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) RARDLL _FILE_OFFSET_BITS=64 _LARGEFILE_SOURCE', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
