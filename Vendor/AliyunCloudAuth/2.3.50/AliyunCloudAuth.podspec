Pod::Spec.new do |s|
  s.name = 'AliyunCloudAuth'
  s.version = '2.3.50'
  s.summary = 'Aliyun CloudAuth iOS SDK binaries for AidRun volunteer liveness verification.'
  s.description = 'Checksum-verified Alibaba CloudAuth ID_PRO face modules and resources used by the native volunteer liveness flow.'
  s.homepage = 'https://www.aliyun.com/product/cloudauth'
  s.license = { :type => 'Commercial', :text => 'Alibaba Cloud Financial-grade ID Verification SDK.' }
  s.author = { 'Alibaba Cloud' => 'https://www.aliyun.com' }
  s.source = { :path => '.' }
  s.platform = :ios, '16.0'
  s.static_framework = true

  s.vendored_frameworks = 'Frameworks/*.framework'
  s.resources = [
    'Resources/APBToygerFacade.bundle',
    'Resources/APBToygerFacadeSuitable.bundle',
    'Resources/BioAuthEngine.bundle',
    'Resources/ToygerService.bundle',
    'PrivacyInfo.xcprivacy'
  ]
  s.frameworks = [
    'Accelerate',
    'AdSupport',
    'AssetsLibrary',
    'AudioToolbox',
    'AVFoundation',
    'CFNetwork',
    'CoreFoundation',
    'CoreGraphics',
    'CoreLocation',
    'CoreMedia',
    'CoreMotion',
    'CoreTelephony',
    'CoreVideo',
    'ImageIO',
    'MobileCoreServices',
    'QuartzCore',
    'Security',
    'SystemConfiguration',
    'UIKit',
    'WebKit'
  ]
  s.libraries = ['c++', 'resolv', 'z']

  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -ObjC'
  }
end
