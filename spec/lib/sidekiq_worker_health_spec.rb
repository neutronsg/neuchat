require 'spec_helper'
require 'sidekiq'
require 'tmpdir'
require_relative '../../lib/sidekiq_worker_health'

RSpec.describe SidekiqWorkerHealth do
  around do |example|
    Dir.mktmpdir do |dir|
      previous = ENV.fetch('WORKER_HEALTH_DIRECTORY', nil)
      ENV['WORKER_HEALTH_DIRECTORY'] = dir
      example.run
    ensure
      ENV['WORKER_HEALTH_DIRECTORY'] = previous
    end
  end

  let(:hooks) { {} }

  before do
    config = instance_double(Sidekiq::Config)
    allow(config).to receive(:on) { |event, &block| hooks[event] = block }
    described_class.install(config)
  end

  it 'requires startup and a successful heartbeat, then becomes unready on quiet' do
    expect(described_class.ready?(Process.pid)).to be(false)
    hooks[:beat].call
    expect(described_class.ready?(Process.pid)).to be(false)
    hooks[:startup].call
    expect(described_class.ready?(Process.pid)).to be(false)
    hooks[:beat].call
    expect(described_class.ready?(Process.pid)).to be(true)
    hooks[:quiet].call
    hooks[:beat].call
    expect(described_class.ready?(Process.pid)).to be(false)
  end

  it 'rejects stale, corrupt and different-process evidence' do
    File.write(described_class.path, '{')
    expect(described_class.ready?(Process.pid)).to be(false)
    File.write(described_class.path, JSON.generate(pid: Process.pid, at: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 30))
    expect(described_class.ready?(Process.pid)).to be(false)
    File.write(described_class.path, JSON.generate(pid: Process.pid + 1, at: Process.clock_gettime(Process::CLOCK_MONOTONIC)))
    expect(described_class.ready?(Process.pid)).to be(false)
  end

  it 'removes readiness on shutdown' do
    hooks[:startup].call
    hooks[:beat].call
    hooks[:shutdown].call
    expect(described_class.ready?(Process.pid)).to be(false)
  end
end
