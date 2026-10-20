#!/usr/bin/env ruby
# Small behavioral checks run against disposable copies, never the learner's files.
require 'tmpdir'
require_relative 'lab'

def exercise(name)
  Dir.mktmpdir('offline-lab-test-') do |directory|
    source = File.expand_path('..', __dir__)
    %w[base clusters local-sources offline-cache inventory].each do |path|
      FileUtils.cp_r(File.join(source, path), directory)
    end
    lab = PracticeLab.new(directory)
    yield lab
    puts "PASS #{name}"
  end
end

def edit(lab, path)
  location = lab.file(path)
  File.write(location, yield(File.read(location)))
end

def expect_failure(message)
  begin
    yield
  rescue StandardError => error
    raise "Wrong diagnostic: #{error.message}" unless error.message.include?(message)
    return
  end
  raise "Expected failure containing #{message.inspect}"
end

exercise('baseline: all six apps across three environments') do |lab|
  PracticeLab::ENVIRONMENTS.each { |env| lab.render(env).each { |result| lab.check(result) } }
end

exercise('shared image edit reaches DTA/STG; PRD override wins') do |lab|
  edit(lab, 'base/workboard/values.yaml') { |text| text.sub('1.4.2', '1.4.3') }
  images = PracticeLab::ENVIRONMENTS.map { |env| lab.summary(lab.render(env, 'workboard').first)[:image] }
  lab.ensure!(images.map { |image| image.split(':').last } == %w[1.4.3 1.4.3 1.4.1], 'Values precedence incorrect')
end

exercise('local template edit does not change pinned chart package') do |lab|
  edit(lab, 'local-sources/HelmCharts/demo-web/templates/deployment.yaml') do |text|
    text.sub('replicas: {{ .Values.replicaCount }}', 'replicas: 7')
  end
  replicas = %w[DTA STG].map { |env| lab.summary(lab.render(env, 'workboard').first)[:replicas] }
  lab.ensure!(replicas == [7, 1], 'Saved chart package changed with local template')
end

exercise('broken route produces useful diagnostic') do |lab|
  edit(lab, 'clusters/STG/lab/local/workboard/route.yaml') { |text| text.sub('name: workboard', 'name: nonexistent') }
  expect_failure('route backend Service nonexistent not found') { lab.check(lab.render('STG', 'workboard').first) }
end

exercise('unresolved external key is detected') do |lab|
  edit(lab, 'clusters/DTA/lab/local/notebook/kustomization.yaml') do |text|
    text.sub('value: notebook-dta-password', 'value: REPLACE_BY_OVERLAY')
  end
  expect_failure('unresolved secret/database placeholder') { lab.check(lab.render('DTA', 'notebook').first) }
end

exercise('wrong storage selector is detected') do |lab|
  edit(lab, 'clusters/PRD/lab/local/workboard/pvc.yaml') { |text| text.sub('environment: prd', 'environment: stg') }
  expect_failure('PVC selector/class/access mode') { lab.check(lab.render('PRD', 'workboard').first) }
end

exercise('missing image inventory entry is detected') do |lab|
  edit(lab, 'clusters/STG/lab/local/workboard/values.yaml') { |text| "image:\n  tag: \"9.9.9\"\n" + text }
  expect_failure('missing from environment inventory') { lab.check(lab.render('STG', 'workboard').first) }
end

exercise('missing values reference fails before rendering') do |lab|
  edit(lab, 'clusters/DTA/lab/local/apps/workboard.yaml') do |text|
    text.sub('$value/base/workboard/values.yaml', '$value/base/workboard/not-here.yaml')
  end
  expect_failure('File not found') { lab.render('DTA', 'workboard') }
end

exercise('StatefulSet inventory identifies its primary workload') do |lab|
  result = lab.render('STG', 'searchbox').first
  lab.check(result)
  lab.ensure!(lab.summary(result)[:workload] == 'StatefulSet', 'Expected StatefulSet')
end

exercise('CronJob schedule errors are detected') do |lab|
  edit(lab, 'clusters/STG/lab/local/scheduler/values.yaml') { |text| text.sub('*/5 * * * *', 'bad cron') }
  expect_failure('CronJob schedule must contain 5 fields') { lab.check(lab.render('STG', 'scheduler').first) }
end

exercise('migration must satisfy the application schema requirement') do |lab|
  edit(lab, 'clusters/DTA/lab/local/identity/values.yaml') { |text| text.sub('enabled: true', 'enabled: false') }
  expect_failure('application requires schema 2') { lab.check(lab.render('DTA', 'identity').first) }
end

exercise('required cache dependency cannot be disabled silently') do |lab|
  edit(lab, 'base/releasehub/values.yaml') { |text| text.sub('enabled: true', 'enabled: false') }
  expect_failure('cache is required') { lab.render('DTA', 'releasehub') }
end

exercise('migration job image must be inventoried') do |lab|
  edit(lab, 'clusters/DTA/lab/local/identity/values.yaml') { |text| text.sub('targetVersion: 2', "targetVersion: 2\n  image: registry.example.invalid/schema-tool:9.9.9") }
  expect_failure('missing from environment inventory') { lab.check(lab.render('DTA', 'identity').first) }
end

exercise('editing dependency source does not rebuild a parent package') do |lab|
  edit(lab, 'local-sources/HelmCharts/demo-cache/templates/cache.yaml') do |text|
    text.sub('replicas: 1', 'replicas: 9')
  end
  result = lab.render('DTA', 'releasehub').first
  cache = result[:objects].find { |item| item['kind'] == 'Deployment' && item.dig('metadata', 'name') == 'releasehub-cache' }
  lab.ensure!(cache.dig('spec', 'replicas') == 1, 'Source dependency unexpectedly replaced packaged dependency')
end

puts '14 behavioral checks passed; no network or cluster used.'
