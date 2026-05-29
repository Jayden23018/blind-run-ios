platform :ios, '16.0'

project 'blindRun', {
  'Debug' => :debug,
  'DemoRelease' => :release,
  'Release' => :release
}

target 'blindRun' do
  use_frameworks!

  # 高德地图 SDK (NO-IDFA 版本，避免审核问题)
  pod 'AMap3DMap-NO-IDFA'
  pod 'AMapLocation-NO-IDFA'
  pod 'AMapSearch-NO-IDFA'

  target 'blindRunTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end

  # 禁用脚本沙箱（Xcode 15+ 默认开启，会阻止 CocoaPods 资源复制脚本）
  # 通过 aggregate target xcconfig 注入到主项目构建设置
  installer.aggregate_targets.each do |target|
    target.xcconfigs.each do |variant, xcconfig|
      xcconfig.attributes['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      # 高德地图 SDK 不含 arm64 模拟器架构，排除以使用 x86_64 (Rosetta) 模拟器
      xcconfig.attributes['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
      target.client_root.join("Pods", "Target Support Files", target.label, "#{target.label}.#{variant.downcase}.xcconfig").open('w') do |f|
        f.write(xcconfig.to_s)
      end
    end
  end
end
