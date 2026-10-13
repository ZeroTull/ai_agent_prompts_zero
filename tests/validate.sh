#!/usr/bin/env bash
# Checks that every agent, skill and command is cataloged, loadable by Claude Code, documented,
# and that our own entries carry the safety rules. Also checks both settings files.
# Usage: tests/validate.sh [repo-dir]   (defaults to this repo)
# Runs as one Ruby process so the whole check stays fast.
set -uo pipefail

REPO="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"

exec ruby -ryaml -rjson - "$REPO" <<'RUBY'
repo = ARGV[0]
errors = []
err = ->(msg) { errors << msg }
rel = ->(path) { path.delete_prefix("#{repo}/") }
read = ->(path) { File.exist?(path) ? File.read(path) : "" }

safety = read.call("#{repo}/templates/safety.md").strip
err.call("templates/safety.md missing or empty") if safety.empty?
readme = read.call("#{repo}/README.md")
template = read.call("#{repo}/templates/CLAUDE.md")
listed = ->(name, text) { text.match?(/`\/?#{Regexp.escape(name)}`/) }

def entry_file(repo, name, kind)
  { "agent" => "#{repo}/agents/#{name}.md",
    "skill" => "#{repo}/skills/#{name}/SKILL.md",
    "command" => "#{repo}/commands/#{name}.md" }[kind]
end

check_frontmatter = lambda do |file, expected|
  m = File.read(file).match(/\A---\n(.*?)\n---\n/m)
  return err.call("#{rel.call(file)}: missing frontmatter block") unless m
  begin
    data = YAML.safe_load(m[1])
  rescue Psych::Exception => e
    return err.call("#{rel.call(file)}: invalid YAML: #{e.message.lines.first.strip}")
  end
  return err.call("#{rel.call(file)}: frontmatter is not a mapping") unless data.is_a?(Hash)
  name, desc, model = data.values_at("name", "description", "model").map { |v| v.to_s.gsub(/\s+/, " ") }
  err.call("#{rel.call(file)}: name '#{name}' does not match '#{expected}'") unless name == expected
  err.call("#{rel.call(file)}: name '#{name}' is not kebab-case") unless name.match?(/\A[a-z0-9]+(-[a-z0-9]+)*\z/)
  err.call("#{rel.call(file)}: description missing or too short") if desc.length < 40
  unless model.empty? || model.match?(/\A(inherit|opus|sonnet|haiku|claude-[a-z0-9.-]+)\z/)
    err.call("#{rel.call(file)}: unknown model '#{model}'")
  end
end

# ── catalog ──────────────────────────────────────────────────────────────────
cataloged = {}
catalog = "#{repo}/catalog.tsv"
if !File.exist?(catalog)
  err.call("catalog.tsv missing")
else
  lines = File.read(catalog).lines.map(&:chomp)
  err.call("catalog.tsv: bad header") unless lines.first == "name\tkind\tgroup\tsource"
  lines.drop(1).reject(&:empty?).each do |line|
    name, kind, group, source, *extra = line.split("\t", -1)
    row = "catalog.tsv: #{name}"
    err.call("#{row}: more than 4 columns") unless extra.empty?
    next err.call("#{row}: unknown kind '#{kind}'") unless %w[agent skill command].include?(kind)
    err.call("#{row}: unknown group '#{group}'") unless %w[qa personal third-party].include?(group)
    if group == "third-party"
      err.call("#{row}: third-party entry needs a source URL") unless source.to_s.start_with?("https://")
    elsif source != "-"
      err.call("#{row}: source must be '-' for our own entries")
    end
    err.call("#{row}: duplicate entry") if cataloged.key?("#{kind}:#{name}")
    cataloged["#{kind}:#{name}"] = true

    file = entry_file(repo, name, kind)
    next err.call("#{row}: #{rel.call(file)} does not exist") unless File.file?(file)
    check_frontmatter.call(file, name) unless kind == "command"
    if group != "third-party" && !File.read(file).include?(safety)
      err.call("#{rel.call(file)}: does not contain the block from templates/safety.md verbatim")
    end
    err.call("#{name} not listed in README.md") unless listed.call(name, readme)
    err.call("#{name} not listed in templates/CLAUDE.md") if group == "qa" && !listed.call(name, template)
  end
end

# Every entry on disk must be cataloged.
entries = 0
Dir.glob("#{repo}/agents/*.md").sort.each do |f|
  entries += 1
  err.call("agents/#{File.basename(f)} is not in catalog.tsv") unless cataloged["agent:#{File.basename(f, '.md')}"]
end
Dir.glob("#{repo}/skills/*/").sort.each do |d|
  entries += 1
  name = File.basename(d)
  # Exact-case check: macOS finds skill.md as SKILL.md, Linux does not.
  err.call("skills/#{name}: missing SKILL.md (exact case)") unless Dir.children(d).include?("SKILL.md")
  err.call("skills/#{name} is not in catalog.tsv") unless cataloged["skill:#{name}"]
end
Dir.glob("#{repo}/commands/*.md").sort.each do |f|
  entries += 1
  err.call("commands/#{File.basename(f)} is not in catalog.tsv") unless cataloged["command:#{File.basename(f, '.md')}"]
end

# ── settings ─────────────────────────────────────────────────────────────────
# settings.example.json: core secret rules present, committed .env templates readable.
# settings.json: valid, portable, and denies at least everything the example denies.
load_settings = lambda do |path|
  data = JSON.parse(File.read(path))
  perms = data.is_a?(Hash) ? data["permissions"] : nil
  [data, perms.is_a?(Hash) && perms["deny"].is_a?(Array) ? perms["deny"] : []]
rescue Errno::ENOENT
  err.call("#{File.basename(path)} is missing")
  nil
rescue JSON::ParserError
  err.call("#{File.basename(path)} is not valid JSON")
  nil
end

example = load_settings.call("#{repo}/settings.example.json")
if example
  deny = example[1]
  required = ["Read(**/.env)", "Read(**/.env.local)", "Read(**/.env.production)", "Read(**/.env.test)",
              "Read(**/secrets/**/*.yaml)", "Read(**/secrets/**/*.yml)", "Read(**/secrets/**/*.json)",
              "Read(**/secrets/**/*.properties)", "Read(**/secrets/**/*.env)", "Read(**/secrets/**/*.conf)",
              "Read(**/secrets/**/*.txt)",
              "Read(~/.ssh/**)", "Read(~/.azure/**)", "Read(~/.config/gh/**)", "Read(**/*.pem)"]
  missing = required - deny
  err.call("settings.example.json misses deny rules: #{missing.join(', ')}") unless missing.empty?
  wild = deny.grep(/\ARead\((\*\*\/)?\.env\.\*\)\z/)
  err.call("settings.example.json denies .env templates via #{wild.join(', ')}") unless wild.empty?
  full = load_settings.call("#{repo}/settings.json")
  if full
    gap = deny - full[1]
    err.call("settings.json misses deny rules from settings.example.json: #{gap.join(', ')}") unless gap.empty?
    err.call("settings.json contains a machine-specific /Users/ path") if JSON.generate(full[0]).include?("/Users/")
  end
end

errors.each { |e| puts "FAIL: #{e}" }
if errors.empty?
  puts "validate: all checks passed (#{entries} entries)"
else
  exit 1
end
RUBY
