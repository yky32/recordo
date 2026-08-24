#!/usr/bin/env ruby
# Idempotent: ensure RecordoLiveActivity widget extension is in Runner.xcodeproj
require 'xcodeproj'
ROOT = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ROOT, 'ios/Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
ext = project.targets.find { |t| t.name == 'RecordoLiveActivity' }
if ext
  puts "RecordoLiveActivity already present"
  # Ensure embed order
  embed = runner.copy_files_build_phases.find { |ph| ph.name == 'Embed Foundation Extensions' }
  if embed
    runner.build_phases.delete(embed)
    res_idx = runner.build_phases.index { |p| p.isa == 'PBXResourcesBuildPhase' }
    runner.build_phases.insert(res_idx ? res_idx + 1 : 3, embed)
    project.save
    puts "embed phase reordered before Thin Binary"
  end
  exit 0
end
puts "Target missing — re-run full setup from agent history or docs"
exit 1
