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
  # ⚠️ 不要把 PrivacyInfo.xcprivacy 加回这里。s.resources 是**平铺**复制到 App bundle 根目录，
  # 而根目录那份就是**主 App 自己的**隐私清单槽位 —— 加回去会同时造成两个后果：
  #   ① 与 blindRun/PrivacyInfo.xcprivacy 撞车，报 "Multiple commands produce .../PrivacyInfo.xcprivacy"
  #   ② 编译过了的话更糟：阿里云的清单会冒充主 App 的对外声明（它带 NSPrivacyCollectedDataTypes
  #      DeviceID/Linked，且 purpose 写的 "Protect Device Security" 不是 Apple 的合法取值）
  # 本 SDK 的 10 个 framework 全是静态库（`file` 显示 ar archive），静态库的代码被链进主二进制，
  # 所以它用到的 required reason API 必须由**主 App 的**清单声明 —— 已在 blindRun/PrivacyInfo.xcprivacy
  # 里按 Apple 允许 App 声明的 reason code 声明（DiskSpace/FileTimestamp），不靠这个文件。
  # 守卫：scripts/hooks/guard.mjs 的 `vendor-privacy-manifest` 规则。
  s.resources = [
    'Resources/APBToygerFacade.bundle',
    'Resources/APBToygerFacadeSuitable.bundle',
    'Resources/BioAuthEngine.bundle',
    'Resources/ToygerService.bundle'
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
