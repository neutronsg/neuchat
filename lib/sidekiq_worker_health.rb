require 'json'
require 'fileutils'

# A fresh successful Sidekiq Redis heartbeat, not merely a live Ruby process.
module SidekiqWorkerHealth
  def self.path(pid = Process.pid)
    File.join(ENV.fetch('WORKER_HEALTH_DIRECTORY', '/tmp'), "sidekiq-health-#{pid}.json")
  end

  def self.install(config)
    accepting = false
    mutex = Mutex.new
    config.on(:startup) { mutex.synchronize { accepting = true } }
    config.on(:beat) do
      mutex.synchronize do
        next unless accepting

        target = path
        File.write("#{target}.tmp", JSON.generate(pid: Process.pid, at: Process.clock_gettime(Process::CLOCK_MONOTONIC)))
        File.rename("#{target}.tmp", target)
      end
    end
    stop = lambda do
      mutex.synchronize do
        accepting = false
        FileUtils.rm_f(path)
      end
    end
    config.on(:quiet, &stop)
    config.on(:shutdown, &stop)
  end

  def self.ready?(pid, max_age: 20)
    Process.kill(0, pid)
    state = JSON.parse(File.read(path(pid)))
    age = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state.fetch('at')
    state.fetch('pid') == pid && age >= 0 && age < max_age
  rescue SystemCallError, JSON::ParserError, KeyError, TypeError
    false
  end
end
