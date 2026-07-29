Pod::Spec.new do |s|
  s.name             = 'facebook_app_events'
  s.version          = '0.30.2+company.3'
  s.summary          = 'Flutter plugin for Facebook Analytics and App Events'
  s.description      = <<-DESC
Flutter plugin for Facebook Analytics and App Events
                       DESC
  s.homepage         = 'https://github.com/oddbit/flutter_facebook_app_events'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Oddbit Team' => 'opensource@oddbit.id' }
  s.source           = { :path => '.' }
  s.source_files = 'facebook_app_events/Sources/facebook_app_events/**/*.{swift}'
  s.static_framework = true
  s.dependency 'Flutter'
  s.swift_version       = '5.9'
  s.ios.deployment_target = '13.0'

  # This company fork pins the native SDK version verified by its native build checks.
  s.dependency 'FBSDKCoreKit', '18.1.0'
end
