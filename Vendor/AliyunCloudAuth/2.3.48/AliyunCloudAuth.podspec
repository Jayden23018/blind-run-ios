Pod::Spec.new do |s|
  s.name = 'AliyunCloudAuth'
  s.version = '2.3.48'
  s.summary = 'Aliyun CloudAuth iOS SDK binaries for AidRun volunteer liveness verification.'
  s.description = 'Vendored Aliyun CloudAuth frameworks used to collect metaInfo for backend-driven liveness verification.'
  s.homepage = 'https://www.aliyun.com/product/cloudauth'
  s.license = { :type => 'Commercial', :text => 'Provided for AidRun iOS integration by the backend team.' }
  s.author = { 'AidRun' => 'dev@aidrun.local' }
  s.source = { :path => '.' }
  s.platform = :ios, '16.0'
  s.static_framework = true

  s.vendored_frameworks = 'Frameworks/*.framework'
  s.resources = [
    'Resources/BioAuthEngine.bundle',
    'PrivacyInfo.xcprivacy'
  ]
  s.frameworks = [
    'AVFoundation',
    'CoreMedia',
    'CoreVideo',
    'CoreGraphics',
    'UIKit',
    'WebKit',
    'SystemConfiguration',
    'Security',
    'CoreTelephony',
    'QuartzCore'
  ]
  s.libraries = ['c++', 'resolv']

  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC'
  }
end
