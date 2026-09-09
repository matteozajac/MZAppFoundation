#!/usr/bin/env ruby
# Native Xcode wiring; does not rewrite app feature code.
require 'json'
require 'pathname'
require 'xcodeproj'
root = Pathname.new(ARGV.fetch(0))
config = JSON.parse(ARGV.fetch(1))
project = Xcodeproj::Project.open(root.join(config.fetch('project')).to_s)
target = project.targets.find { |t| t.name == config.fetch('target') }
raise 'Target not found' unless target
local_name = target.name + 'Local'
local = project.targets.find { |t| t.name == local_name }
platform = config['platform'] == 'iOS' ? :ios : :visionos
unless local
  local = project.new_target(:application, local_name, platform, config.fetch('deployment_target', '26.0'))
  target.build_configurations.each do |original|
    dest = local.add_build_configuration(original.name, original.type)
    dest.build_settings = Marshal.load(Marshal.dump(original.build_settings))
    dest.base_configuration_reference = original.base_configuration_reference
  end
  [[:source_build_phase, :source_build_phase], [:resources_build_phase, :resources_build_phase], [:frameworks_build_phase, :frameworks_build_phase]].each do |source_name, dest_name|
    target.public_send(source_name).files.each do |file|
      next unless file.file_ref
      local.public_send(dest_name).add_file_reference(file.file_ref, true).settings = file.settings
    end
  end
  target.dependencies.each { |dependency| local.add_dependency(dependency.target) if dependency.target }
end
vendor_products = %w[RevenueCat RevenueCatUI Sentry Sentry-Dynamic FirebaseAnalytics FirebaseAnalyticsCore FirebaseCore Pulse PulseUI PulseProxy]
[target, local].each do |t|
  t.package_product_dependencies.to_a.each do |dependency|
    next unless vendor_products.include?(dependency.product_name)
    t.frameworks_build_phase.files.to_a.select { |f| f.product_ref == dependency }.each(&:remove_from_project)
    dependency.remove_from_project
  end
end
package = project.root_object.package_references.find do |ref|
  (ref.respond_to?(:repositoryURL) && ref.repositoryURL == 'git@github.com:matteozajac/MZAppFoundation.git') ||
    (ref.respond_to?(:relative_path) && ref.relative_path == config['package_path'])
end
unless package
  if config['package_path']
    package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    package.relative_path = config['package_path']
  else
    package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    package.repositoryURL = 'git@github.com:matteozajac/MZAppFoundation.git'
    package.requirement = { 'kind' => 'exactVersion', 'version' => config.fetch('package_version', '0.1.0') }
  end
  project.root_object.package_references << package
end
group = project.main_group.find_subpath('.mzappfoundation/Generated', true)
group.set_source_tree('SOURCE_ROOT')
group.path = '.mzappfoundation/Generated'
bootstrap = group.files.find { |f| f.path == 'MZBootstrap.swift' } || group.new_file('MZBootstrap.swift')
[target, local].each do |t|
  name = t == local ? 'MZAppFoundation' : (config['platform'] == 'iOS' ? 'MZAppFoundationFirebase' : 'MZAppFoundationLive')
  dependency = t.package_product_dependencies.find { |d| d.product_name == name }
  unless dependency
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package if package.isa == 'XCRemoteSwiftPackageReference'
  dependency.product_name = name
  t.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  t.frameworks_build_phase.files << build_file
  end
  t.source_build_phase.add_file_reference(bootstrap, true)
  if config.fetch('providers', {})['google_service_info']
    reference = group.files.find { |f| f.path == 'GoogleService-Info.plist' } || group.new_file('GoogleService-Info.plist')
    t.resources_build_phase.add_file_reference(reference, true)
  end
  unless t.build_configurations.any? { |c| c.name == 'Internal' }
    internal = t.add_build_configuration('Internal', :release)
    release = t.build_configurations.find { |c| c.name == 'Release' }
    internal.build_settings = Marshal.load(Marshal.dump(release.build_settings)) if release
  end
  t.build_configurations.each do |c|
    settings = c.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = config['bundle_id']
    settings['SUPPORTED_PLATFORMS'] = config['platform'] == 'iOS' ? (t == local ? 'iphonesimulator' : 'iphoneos') : (t == local ? 'xrsimulator' : 'xros')
    flags = Array(settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] || '$(inherited)').flat_map(&:split).reject { |f| ['MZ_LOCAL', 'MZ_INTERNAL'].include?(f) }
    flags << 'MZ_LOCAL' if t == local
    flags << 'MZ_INTERNAL' if c.name == 'Internal'
    settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = flags.uniq.join(' ')
    settings['INFOPLIST_KEY_FirebaseAutomaticScreenReportingEnabled'] = 'NO'
    settings['INFOPLIST_KEY_FIREBASE_ANALYTICS_COLLECTION_ENABLED'] = 'NO'
    settings['INFOPLIST_KEY_GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED'] = 'NO'
    settings['INFOPLIST_KEY_GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS'] = 'NO'
    plist_path = settings['INFOPLIST_FILE']
    if plist_path && !plist_path.include?('$')
      absolute = root.join(plist_path)
      plist = absolute.exist? ? Xcodeproj::Plist.read_from_path(absolute.to_s) : {}
      if config['platform'] == 'visionOS'
        scene = plist['UIApplicationSceneManifest'] ||= {}
        scene['UIApplicationSupportsMultipleScenes'] = true
        scene['UIApplicationPreferredDefaultSceneSessionRole'] ||= 'UIWindowSceneSessionRoleApplication'
      end
      urls = plist['CFBundleURLTypes'] ||= []
      urls << { 'CFBundleURLSchemes' => [config['url_scheme']] } unless urls.any? { |u| Array(u['CFBundleURLSchemes']).include?(config['url_scheme']) }
      %w[FirebaseAutomaticScreenReportingEnabled FIREBASE_ANALYTICS_COLLECTION_ENABLED GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS].each { |key| plist[key] = false }
      absolute.dirname.mkpath
      Xcodeproj::Plist.write_to_path(plist, absolute.to_s)
    else
      # Generated Info.plist URL array is supplied through a concrete companion plist.
      absolute = root.join('.mzappfoundation/Generated/App-Info.plist')
      plist = {'CFBundleURLTypes' => [{'CFBundleURLSchemes' => [config['url_scheme']]}]}
      if config['platform'] == 'visionOS'
        plist['UIApplicationSceneManifest'] = {'UIApplicationSupportsMultipleScenes' => true, 'UIApplicationPreferredDefaultSceneSessionRole' => 'UIWindowSceneSessionRoleApplication'}
      end
      Xcodeproj::Plist.write_to_path(plist, absolute.to_s)
      settings['INFOPLIST_FILE'] = '.mzappfoundation/Generated/App-Info.plist'
      settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    end
  end
  if t == target && config.fetch('providers', {})['sentry_dsn']
    phase = t.shell_script_build_phases.find { |p| p.name == 'MZ Sentry Symbols' } || t.new_shell_script_build_phase('MZ Sentry Symbols')
    phase.shell_script = 'python3 "$SRCROOT/.mzappfoundation/Generated/upload_symbols.py"'
    phase.always_out_of_date = '1'
    t.build_configurations.each { |c| c.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO' }
  end
end
project.add_build_configuration('Internal', :release)
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(local)
scheme.set_launch_target(local)
scheme.save_as(project.path, local_name, true)
puts "Configured #{target.name} and #{local.name}"
