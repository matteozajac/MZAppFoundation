require 'xcodeproj'
require 'json'
require 'pathname'

root = Pathname.new(ARGV.fetch(0))
config = JSON.parse(ARGV.fetch(1))
project = Xcodeproj::Project.open(root.join(config.fetch('project')))
errors = []
[config.fetch('target'), config.fetch('target') + 'Local'].each do |name|
  target = project.targets.find { |item| item.name == name }
  unless target
    errors << "Missing target #{name}"
    next
  end
  target.build_configurations.each do |configuration|
    inherited = project.build_configurations.find { |item| item.name == configuration.name }&.build_settings || {}
    settings = inherited.merge(configuration.build_settings)
    description = settings['INFOPLIST_KEY_NSMicrophoneUsageDescription']
    path = settings['INFOPLIST_FILE']
    if path && !path.include?('$') && root.join(path).file?
      description ||= Xcodeproj::Plist.read_from_path(root.join(path).to_s)['NSMicrophoneUsageDescription']
    end
    unless description.is_a?(String) && !description.strip.empty?
      errors << "#{name}/#{configuration.name} is missing NSMicrophoneUsageDescription; verify inherited xcconfig values manually if applicable"
    end
  end
end
puts JSON.generate(errors)
