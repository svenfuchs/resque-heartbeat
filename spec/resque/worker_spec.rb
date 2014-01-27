require 'rake'
require 'resque/tasks'
require 'resque_heartbeat'
require 'logger'

describe Resque::Worker do
  QUEUE_NAME = SecureRandom.uuid
  let(:worker_max_start_seconds){ 6 }
  let(:worker_max_shutdown_seconds){ 10 }
  let(:logger) do
    ret = Logger.new(STDOUT)
    ret.level = Logger::FATAL
    ret
  end
  let!(:start_infos){ [start_worker, start_worker] }
  let(:workers){ start_infos.map(&:first) }
  let(:pids){ start_infos.map(&:last) }

  before(:each) do
    connect_redis
    Redis.new.ping rescue raise "redis server isn't up"
  end

  after(:each) do
    Resque.redis.srem "queues", QUEUE_NAME
  end

  def connect_redis
    Resque.redis = Redis.new
  end

  def log(*args)
    logger.debug(*args)
  end

  class TestWorker
    @queue = QUEUE_NAME
    def self.perform
      raise "bye"
      log "working in pid #{Process.pid}"
      log caller
    end
  end

  def get_worker(pid)
    matching = Resque.workers.select{|w| w.id.split(':')[1].to_i == pid}
    raise "Found multiple workers with pid #{pid}" if matching.count > 1
    matching.first
  end

  def poll_infinite(interval_secs)
    until last_ret = yield do
      sleep(interval_secs)
    end
    last_ret
  end

  def poll(interval_secs, max_secs, action_msg)
    begin
      Timeout::timeout(max_secs) do
        poll_infinite(interval_secs) { yield }
      end
    rescue Timeout::Error
      raise "Worker didn't #{action_msg} in time"
    end
  end

  def start_worker
    pid = fork do
      begin
        connect_redis # you have to reconnect after forking
        ENV['QUEUE']=QUEUE_NAME
        ENV['TERM_CHILD'] = '1'
        Rake::Task['resque:work'].reenable
        Rake::Task['resque:work'].invoke
      rescue => e
        log e.message
        log e.backtrace
      end
      log "Worker process complete"
    end

    log "Waiting for worker #{pid} to start..."

    worker =  poll(1, worker_max_start_seconds, "come up") { get_worker(pid) }

    raise "The worker is dead" if worker.dead?
    log "Worker #{pid} has started."
    [worker, pid]
  end

  def is_heart_beating?(worker, duration_seconds)
    log "Checking whether the worker's heartbeat is updating"
    pre = worker.heart.ttl
    sleep(duration_seconds) # give it some time to update the ttl
    post = worker.heart.ttl
    pre - duration_seconds > post
  end

  it "heartbeat starts and stops normally" do
    begin
      workers.each do |worker|
        is_heart_beating?(worker, 3).should be_false
      end
    ensure
      pids.each{|pid| Process.kill('INT', pid)}
    end
  end

  context "with a dead worker" do
    let(:dead_pid){ pids.first }
    let(:dead_worker){ workers.first }
    let(:live_worker){ workers.last }

    before(:each) do
      log "Killing worker #{dead_pid}"
      Process.kill("KILL", dead_pid)
    end

    it "doesn't update the heartbeat" do
      is_heart_beating?(dead_worker, 5).should be_false
    end

    def force_dead
      # Don't need to wait full TTL. Simulate it by removing the key
      Resque.redis.del dead_worker.heart.key
    end

    context "#dead?" do
      before(:each) do
        force_dead
      end

      it "is true for the dead worker" do
        dead_worker.dead?.should be_true
      end

      it "is false for the rest of the workers" do
        live_worker.dead?.should be_false
      end
    end

    context "Resque.prune_dead_workers!" do
      before(:each) do
        raise "Worker cleaned up too early" if get_worker(dead_pid).nil?
        force_dead
        Resque.prune_dead_workers!
      end

      it "removes dead workers and their heartbeats" do
        dead_worker.heart.ttl.should be < 0
        Resque.workers.map(&:id).should_not include(dead_worker.id)
      end

      it "leaves live workers and their heartbeats intact" do
        live_worker.heart.ttl.should be > 0
        Resque.workers.map(&:id).should include(live_worker.id)
      end
    end
  end
end
