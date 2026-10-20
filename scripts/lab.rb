#!/usr/bin/env ruby
# Offline only: invokes Helm and `kubectl kustomize`, never an API server.
require 'yaml'
require 'json'
require 'open3'
require 'fileutils'

class PracticeLab
  ENVIRONMENTS = %w[DTA STG PRD].freeze
  attr_reader :root

  def initialize(root = File.expand_path('..', __dir__))
    @root = File.expand_path(root)
  end

  def file(path)
    absolute = File.expand_path(path, root)
    raise "Path outside lab: #{path}" unless absolute.start_with?(root + '/')
    raise "File not found: #{path}" unless File.exist?(absolute)
    absolute
  end

  def yaml(text)
    YAML.safe_load(text, aliases: true) || {}
  end

  def documents(text)
    text.split(/^---\s*$/).map { |part| yaml(part) }.reject(&:empty?)
  end

  def run(*args)
    output, error, status = Open3.capture3(*args)
    raise "#{args.first} failed: #{error.strip}" unless status.success?
    output
  end

  def applications(env)
    raise "Choose DTA, STG or PRD" unless ENVIRONMENTS.include?(env)
    Dir.glob(File.join(root, 'clusters', env, '*', '*', 'apps', '*.yaml')).sort
       .map { |path| [path, yaml(File.read(path))] }
       .select { |_, doc| doc['kind'] == 'Application' }
       .tap { |entries| raise "No Applications found for #{env}" if entries.empty? }
  end

  def inventory(env, kind)
    JSON.parse(File.read(file("inventory/#{env}/#{kind}.json")))
  end

  def chart_for(source, env)
    return file(source.fetch('path')) unless source['chart']
    entry = inventory(env, 'charts').find do |item|
      item['source_repo'] == source['repoURL'] &&
        item['chart_name'] == source['chart'] &&
        item['version'] == source['targetRevision']
    end
    raise "No offline chart inventory match for #{source['chart']} #{source['targetRevision']}" unless entry
    file(entry.fetch('offline_package'))
  end

  def value_files(application, helm)
    helm.fetch('valueFiles').map do |reference|
      match = reference.match(/^\$([^\/]+)\/(.+)$/)
      raise "Expected a $ref/path values reference: #{reference}" unless match
      source = application.fetch('spec').fetch('sources').find { |item| item['ref'] == match[1] }
      raise "Missing Git source alias #{match[1]}" unless source
      # $ref paths are relative to repository root, not source.path.
      file(match[2])
    end
  end

  def render(env, name = nil)
    selected = applications(env).select { |_, app| !name || app.dig('spec', 'sources', 0, 'helm', 'releaseName') == name }
    raise "Unknown app #{name} in #{env}" if selected.empty?
    selected.map do |path, application|
      spec = application.fetch('spec')
      sources = spec.fetch('sources')
      helm_source = sources.find { |item| item['helm'] }
      raise "No Helm source in #{path}" unless helm_source
      helm = helm_source.fetch('helm')
      chart = chart_for(helm_source, env)
      args = ['helm', 'template', helm.fetch('releaseName'), chart,
              '--namespace', spec.fetch('destination').fetch('namespace'), '--kube-version', '1.30.0']
      value_files(application, helm).each { |value| args.concat(['--values', value]) }
      helm_output = run(*args)
      extras = sources.select { |item| item['ref'] && item['path'] }
                      .map { |item| run('kubectl', 'kustomize', file(item['path'])) }.join("\n---\n")
      objects = documents(helm_output + "\n---\n" + extras)
      metadata = yaml(run('helm', 'show', 'chart', chart))
      if helm_source['chart']
        ensure!(metadata['version'] == helm_source['targetRevision'],
                "#{env}: saved chart package version differs from Application targetRevision")
      end
      { env: env, name: helm.fetch('releaseName'), path: path, application: application,
        metadata: metadata, helm: helm_output, extras: extras, objects: objects }
    end
  end

  def ensure!(condition, message)
    raise message unless condition
  end

  def workloads(objects)
    objects.map do |object|
      kind = object['kind']
      template = case kind
                 when 'Deployment', 'StatefulSet', 'Job'
                   object.dig('spec', 'template')
                 when 'CronJob'
                   object.dig('spec', 'jobTemplate', 'spec', 'template')
                 end
      next unless template
      { object: object, pod: template.fetch('spec'), labels: template.dig('metadata', 'labels') || {} }
    end.compact
  end

  def check(result)
    objects = result.fetch(:objects)
    consumers = workloads(objects)
    namespace = result[:application].dig('spec', 'destination', 'namespace')
    label = "#{result[:env]}/#{result[:name]}"
    objects.each do |object|
      next if object['kind'] == 'PersistentVolume'
      ensure!(object.dig('metadata', 'namespace') == namespace,
              "#{label}: #{object['kind']} namespace differs from Application destination")
    end
    ensure!(!objects.to_json.include?('REPLACE_BY_OVERLAY'), "#{label}: unresolved secret/database placeholder")
    objects.select { |item| item['kind'] == 'HTTPRoute' }.each do |route|
      route.fetch('spec').fetch('rules').each do |rule|
        rule.fetch('backendRefs').each do |backend|
          service = objects.find do |item|
            item['kind'] == 'Service' && item.dig('metadata', 'name') == backend['name'] &&
              item.dig('metadata', 'namespace') == (backend['namespace'] || namespace)
          end
          ensure!(service, "#{label}: route backend Service #{backend['name']} not found")
          ensure!(service.dig('spec', 'ports').any? { |port| port['port'] == backend['port'] },
                  "#{label}: route backend port does not match Service")
        end
      end
    end
    objects.select { |item| item['kind'] == 'Service' }.each do |service|
      selector = service.dig('spec', 'selector')
      workload = consumers.find do |item|
        selector.all? { |key, value| item[:labels][key] == value }
      end
      ensure!(workload, "#{label}: Service selector matches no workload Pod labels")
      container_ports = workload[:pod].fetch('containers').flat_map { |container| container['ports'] || [] }
      service.dig('spec', 'ports').each do |port|
        target = port['targetPort'] || port['port']
        ensure!(container_ports.any? { |entry| target.is_a?(String) ? entry['name'] == target : entry['containerPort'] == target },
                "#{label}: Service targetPort matches no container port")
      end
    end
    consumers.each do |workload|
      pod = workload[:pod]
      (pod.fetch('containers') + pod.fetch('initContainers', [])).each do |container|
        image = container.fetch('image')
        ensure!(inventory(result[:env], 'images').any? { |item| "#{item['source_repo']}:#{item['tag']}" == image },
                "#{label}: image #{image} is missing from environment inventory")
        container.fetch('env', []).each do |variable|
          if variable['name'] == 'CACHE_SERVICE'
            ensure!(objects.any? { |item| item['kind'] == 'Service' && item.dig('metadata', 'name') == variable['value'] },
                    "#{label}: declared cache Service is missing")
          end
          secret = variable.dig('valueFrom', 'secretKeyRef')
          next unless secret
          producer = objects.find { |item| item['kind'] == 'ExternalSecret' && item.dig('spec', 'target', 'name') == secret['name'] }
          ensure!(producer && producer.dig('spec', 'data').any? { |mapping| mapping['secretKey'] == secret['key'] },
                  "#{label}: no ExternalSecret maps the referenced Secret/key")
        end
      end
      pod.fetch('volumes', []).each do |volume|
        claim = volume.dig('persistentVolumeClaim', 'claimName')
        next unless claim
        pvc = objects.find { |item| item['kind'] == 'PersistentVolumeClaim' && item.dig('metadata', 'name') == claim }
        ensure!(pvc, "#{label}: workload PVC #{claim} not found")
      end
    end
    objects.select { |item| item['kind'] == 'CronJob' }.each do |cron|
      ensure!(cron.dig('spec', 'schedule').to_s.split.length == 5,
              "#{label}: CronJob schedule must contain 5 fields")
      ensure!(%w[Allow Forbid Replace].include?(cron.dig('spec', 'concurrencyPolicy')),
              "#{label}: invalid CronJob concurrencyPolicy")
    end
    objects.select { |item| item.dig('metadata', 'labels', 'practice.example.invalid/schema-plan') == 'true' }.each do |plan|
      data = plan.fetch('data')
      current = Integer(data.fetch('currentVersion'))
      required = Integer(data.fetch('requiredVersion'))
      enabled = data.fetch('migrationEnabled') == 'true'
      target = enabled ? Integer(data.fetch('migrationTarget')) : current
      ensure!(target >= current, "#{label}: schema downgrade is not a migration plan")
      ensure!(target >= required, "#{label}: application requires schema #{required}; enable/prepare the migration")
      if enabled
        ensure!(objects.any? { |item| item['kind'] == 'Job' && item.dig('metadata', 'name') == "#{result[:name]}-migrate-v#{target}" },
                "#{label}: migration plan has no matching Job")
      end
    end
    objects.select { |item| item['kind'] == 'PersistentVolumeClaim' }.each do |claim|
      selector = claim.dig('spec', 'selector', 'matchLabels') || {}
      matches = objects.select do |volume|
        volume['kind'] == 'PersistentVolume' &&
          selector.all? { |key, value| volume.dig('metadata', 'labels', key) == value } &&
          volume.dig('spec', 'storageClassName') == claim.dig('spec', 'storageClassName') &&
          (claim.dig('spec', 'accessModes') - volume.dig('spec', 'accessModes')).empty?
      end
      ensure!(matches.length == 1, "#{label}: PVC selector/class/access mode does not match exactly one lab PV")
    end
    true
  end

  def save(result)
    directory = File.join(root, 'rendered', result[:env])
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "#{result[:name]}.yaml"),
               "# OFFLINE WORKING-TREE RENDER. Not proof of deployed state.\n" + result[:helm] + "\n---\n" + result[:extras])
  end

  def summary(result)
    workload = workloads(result[:objects]).find { |item| item[:object].dig('metadata', 'name') == result[:name] }
    raise "No primary workload for #{result[:name]}" unless workload
    app = result[:application]
    { environment: result[:env], application: result[:name],
      chart_source: app.dig('spec', 'sources', 0, 'chart') ? 'offline package (registry stand-in)' : 'local chart',
      chart_version: result[:metadata]['version'], chart_app_version: result[:metadata]['appVersion'],
      workload: workload[:object]['kind'],
      image: workload[:pod].dig('containers', 0, 'image'),
      replicas: workload[:object].dig('spec', 'replicas'),
      schedule: workload[:object].dig('spec', 'schedule'),
      dependencies: result[:metadata].fetch('dependencies', []).map { |item| { name: item['name'], version: item['version'] } },
      git_revision: app.dig('spec', 'sources', 1, 'targetRevision'),
      auto_sync: !!app.dig('spec', 'syncPolicy', 'automated') }
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    lab = PracticeLab.new
    command = ARGV.shift || 'check'
    case command
    when 'check', 'inventory'
      selected_env = ARGV.shift
      selected_app = ARGV.shift
      environments = selected_env ? [selected_env] : PracticeLab::ENVIRONMENTS
      results = environments.flat_map { |env| lab.render(env, selected_app) }
      results.each { |result| lab.check(result); lab.save(result) }
      # STG and PRD intentionally share a pretend cluster. PV identities must be unique there.
      volumes = results.reject { |result| result[:env] == 'DTA' }
                       .flat_map { |result| result[:objects].select { |item| item['kind'] == 'PersistentVolume' } }
      names = volumes.map { |volume| volume.dig('metadata', 'name') }
      lab.ensure!(names.uniq.length == names.length, 'STG/PRD have duplicate cluster-scoped PV names')
      if command == 'inventory'
        puts JSON.pretty_generate(results.map { |result| lab.summary(result) })
      else
        results.each { |result| puts "PASS #{result[:env]}/#{result[:name]}" }
        puts 'Offline references passed. No cluster, network or running images checked.'
      end
    when 'render'
      results = lab.render(ARGV.shift || 'DTA', ARGV.shift)
      results.each { |result| lab.save(result); puts "Rendered #{result[:env]}/#{result[:name]}" }
      puts 'Working-tree files used; declared Git branches are not fetched or simulated.'
    else
      abort 'Usage: ruby scripts/lab.rb check|inventory [DTA|STG|PRD [APP]]; ruby scripts/lab.rb render DTA|STG|PRD [APP]'
    end
  rescue StandardError => error
    warn "FAIL: #{error.message}"
    exit 1
  end
end
