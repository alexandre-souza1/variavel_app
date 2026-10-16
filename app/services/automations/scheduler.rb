module Automations
  # Only dispatches due rules; row locks in Runner serialize multiple workers.
  # Runs with the existing Sidekiq lifecycle, without a new dyno or dependency.
  class Scheduler
    def initialize
      @mutex, @condition, @stopped = Mutex.new, ConditionVariable.new, false
    end

    def start
      @thread = Thread.new do
        loop do
          break if @mutex.synchronize { @stopped }
          begin
            Rails.application.executor.wrap { AutomationDispatchJob.perform_later }
          rescue StandardError => error
            Rails.logger.error("[Automations::Scheduler] error_class=#{error.class.name}")
          end
          @mutex.synchronize { @condition.wait(@mutex, 60) unless @stopped }
        end
      end
    end

    def stop
      @mutex.synchronize { @stopped = true; @condition.broadcast }
      @thread&.join(5)
    end
  end
end
