module Automations
  # Dispatches due automations and opted-in daily summaries. Jobs serialize
  # delivery with row locks and persisted reservations across worker restarts.
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
            Rails.application.executor.wrap { dispatch }
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

    def dispatch
      [AutomationDispatchJob, DailySummaryDispatchJob].each do |job|
        job.perform_later
      rescue StandardError => error
        Rails.logger.error("[Automations::Scheduler] job=#{job.name} error_class=#{error.class.name}")
      end
    end
  end
end
