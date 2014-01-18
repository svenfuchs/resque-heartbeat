require 'resque'

module Resque
  class Worker
    alias_method(:startup_without_heartbeat, :startup)
    def startup_with_heartbeat
      startup_without_heartbeat
      heart.run
    end
    alias_method(:startup, :startup_with_heartbeat)

    alias_method(:unregister_worker_without_heartbeat, :unregister_worker)
    def unregister_worker_with_heartbeat(*args)
      heart.stop
      unregister_worker_without_heartbeat(*args)
    end
    alias_method(:unregister_worker, :unregister_worker_with_heartbeat)

    def heart
      @heart ||= Heart.new(self)
    end

    def remote_hostname
      id.split(':').first
    end

    def dead?
      return heart.dead?
    end

    def prune_if_dead
      return nil unless dead?

      Resque.logger.info "Pruning worker '#{remote_hostname}' from resque"
      unregister_worker
    end

    class Heart
      attr_reader :worker

      class << self
        attr_writer :heartbeat_interval_seconds, :heartbeats_before_dead
      end

      def self.heartbeat_interval_seconds
        @heartbeat_interval_seconds ||= 2
      end

      def self.heartbeats_before_dead
        @heartbeats_before_dead ||= 25
      end


      def initialize(worker)
        @worker = worker
      end

      def run
        @thrd ||= Thread.new do
          loop do
            begin
              beat! && sleep(2)
            rescue Exception => e
              Resque.logger.error "Error while doing heartbeat: #{e} : #{e.backtrace}"
            end
          end
        end
      end

      def stop
        Thread.kill(@thrd)
        redis.del key
      rescue
        nil
      end

      def redis
        Resque.redis
      end

      # you can send a redis wildcard to filter the workers you're looking for
      def Heart.heartbeat_key(worker_name)
        "worker:#{worker_name}:heartbeat"
      end

      def key
        Heart.heartbeat_key worker.remote_hostname
      end

      def beat!
        redis.sadd(:workers, worker)
        redis.setex(key, Heart.heartbeat_interval_seconds * Heart.heartbeats_before_dead, '')
      rescue Exception => e
        Resque.logger.fatal "Unable to set the heartbeat for worker '#{worker.remote_hostname}': #{e} : #{e.backtrace}"
      end

      def dead?
        !redis.exists(key)
      end

      def ttl
        Resque.redis.ttl key
      end
    end
  end

  # NOTE: this assumes all of your workers are putting out heartbeats
  def self.prune_dead_workers!
    begin
      beats = Resque.redis.keys(Worker::Heart.heartbeat_key('*'))
      Worker.all.each do |worker|
        worker.prune_if_dead

        # remove the worker from consideration
        beats.delete worker.heart.key
      end

      # at this point, beats only contains stuff from workers we don't even know about. Ditch 'em.
      beats.each do |key|
        Resque.logger.info "Removing #{key} from heartbeats because the worker isn't talking to Resque."
        Resque.redis.del key
      end
    rescue Exception => e
      p e
    end
  end

  def self.dead_workers
    Worker.all.select{|w| w.dead?}
  end
end
