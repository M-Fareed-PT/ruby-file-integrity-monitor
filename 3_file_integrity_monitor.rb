# 3_file_integrity_monitor.rb
# Usage:
#   ruby 3_file_integrity_monitor.rb <directory> [--baseline baseline.yml]
#   ruby 3_file_integrity_monitor.rb C:\projects --baseline baseline.yml
require 'digest'
require 'yaml'
require 'optparse'
require 'find'
require 'listen'

options = { baseline: "baseline.yml" }
OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{$0} <dir> [--baseline file]"
  opts.on("--baseline F", "Baseline YAML file (default baseline.yml)") { |f| options[:baseline]=f }
end.parse!

dir = ARGV[0] || (raise "directory required: ruby #{$0} <directory>")
unless Dir.exist?(dir)
  raise "Directory not found: #{dir}"
end

def compute_hash(path)
  Digest::SHA256.file(path).hexdigest
rescue
  nil
end

def build_baseline(dir)
  data = {}
  Find.find(dir) do |path|
    next if File.directory?(path)
    h = compute_hash(path)
    data[path] = h if h
  end
  data
end

if !File.exist?(options[:baseline])
  puts "[*] Baseline not found. Building baseline at #{options[:baseline]}..."
  baseline = build_baseline(dir)
  File.write(options[:baseline], baseline.to_yaml)
  puts "[*] Baseline created: #{baseline.size} files."
else
  baseline = YAML.load_file(options[:baseline]) || {}
  puts "[*] Loaded baseline (#{baseline.size} files) from #{options[:baseline]}"
end

puts "[*] Starting watcher on #{dir}..."
listener = Listen.to(dir, ignore: [/\.git/, /node_modules/]) do |modified, added, removed|
  now = Time.now
  modified.each do |f|
    newh = compute_hash(f)
    if baseline[f] && baseline[f] != newh
      puts "[#{now}] MODIFIED: #{f}"
      puts "         old hash: #{baseline[f]}"
      puts "         new hash: #{newh}"
      baseline[f] = newh
    else
      puts "[#{now}] UNKNOWN MODIFIED (no baseline): #{f}"
      baseline[f] = newh
    end
  end
  added.each do |f|
    h = compute_hash(f)
    puts "[#{now}] ADDED: #{f}"
    baseline[f] = h
  end
  removed.each do |f|
    puts "[#{now}] REMOVED: #{f}"
    baseline.delete(f)
  end
  File.write(options[:baseline], baseline.to_yaml)
end

listener.start
puts "[*] Listening. Press Ctrl+C to quit."
sleep
