# frozen_string_literal: true

module Bosh::AzureCloud
  class BatchRequest
    attr_reader :requests, :req_group_key
    def initialize(requests, req_group_key)
      @requests = requests
      @req_group_key = req_group_key
    end
  end

  class TaskWithTimestamp
    attr_reader :req_group_key, :requests_bucket, :request_bucket_mutex, :batching_queue
    def initialize(req_group_key, requests_bucket, request_bucket_mutex, batch_waiting_time, batching_queue)
      @req_group_key = req_group_key
      @requests_bucket = requests_bucket
      @request_bucket_mutex = request_bucket_mutex
      @batching_queue = batching_queue
      @batch_waiting_time = batch_waiting_time
      @task = Concurrent::ScheduledTask.execute(@batch_waiting_time) do
        @request_bucket_mutex.synchronize do
          requests = @requests_bucket[req_group_key]
          @requests_bucket.delete(req_group_key)
          p ("######## requests nil? #{requests==nil}")
          batch_request = BatchRequest.new(requests, req_group_key)
          @batching_queue.push(batch_request)
        end
      end
    end

    def reset
      @task.reset
    end
  end

  class Batch
    # batch_handler is the lambda expression accept the req_param Array do to the batching operation.
    # grouping_func is to group the requests into batch req.
    def initialize(batch_handler, group_key_func)
      # routines
      @batch_handler = batch_handler
      @group_key_func = group_key_func

      # configs
      @check_result_interval = 1

      # request/response
      @raw_request_queue = Queue.new
      @result_bucket = Concurrent::Hash.new
      @result_bucket_lock = Concurrent::ReadWriteLock.new
      @requests_bucket = Concurrent::Hash.new
      @requests_bucket_mutex = Mutex.new
      @batching_queue = Queue.new
      @batching_started = false
      @batching_queue_mutex = Mutex.new

      # delayed task
      @delayed_task_mutex = Mutex.new
      @delayed_task_running = false
      @batch_waiting_time = 3
      @scheduled_tasks = Concurrent::Hash.new
    end

    def execute(request)
      # start the batching if not started.
      @raw_request_queue.push(request)
      _trigger
      req_group_key = @group_key_func.call(request)
      _flushing
      result = _wait_for_result(req_group_key)
      result
    end

    def stop
      # TODO add lock for the queue?
      @raw_request_queue.close
      @batching_queue.close
    end

    private

    def _wait_for_result(req_group_key)
      loop do
        item_available = false
        @result_bucket_lock.with_read_lock do
          item_available = _result_available(req_group_key)
        end
        if item_available
          @result_bucket_lock.with_write_lock do
            item_available = _result_available(req_group_key)
            return _grab_one_fruit(req_group_key) if item_available
          end
        end
        sleep(@check_result_interval)
      end
    end

    # should acquire the write lock of @result_bucket_lock before call this function.
    def _grab_one_fruit(req_group_key)
      value = @result_bucket[req_group_key].pop
      _clean_up(req_group_key)
      value
    end

    def _clean_up(req_group_key)
      @result_bucket.delete(req_group_key) if @result_bucket[req_group_key].empty?
    end

    # should acquire the @result_bucket_lock before call this function.
    def _result_available(req_group_key)
      !@result_bucket[req_group_key].nil? && !@result_bucket[req_group_key].empty?
    end

    def _flushing
      # do the real patching and file the results.
      unless @batching_started
        @batching_queue_mutex.synchronize do
          unless @batching_started
            @batching_started = true
            thread = Thread.new do
              loop do
                batch_request = @batching_queue.pop
                if !batch_request.nil?
                  p "#### got batch request. #{batch_request.nil?}"
                  results = @batch_handler.call(batch_request.requests)
                  @result_bucket_lock.with_write_lock do
                    if @result_bucket[batch_request.req_group_key].nil?
                      @result_bucket[batch_request.req_group_key] = []
                    end
                    results.each do |result|
                      @result_bucket[batch_request.req_group_key].push(result)
                    end
                  end
                elsif !@batching_queue.closed?
                  raise "the request is nil but batching_queue not closed." 
                else
                  break
                end
              end
            end
            thread.abort_on_exception = true
          end
        end
      end
    end

    def _trigger
      unless @delayed_task_running
        @delayed_task_mutex.synchronize do
          unless @delayed_task_running
            @delayed_task_running = true
            thread = Thread.new do
              loop do
                request = @raw_request_queue.pop
                if !request.nil?
                  req_group_key = @group_key_func.call(request)

                  @requests_bucket_mutex.synchronize do
                    if @requests_bucket[req_group_key].nil?
                      @requests_bucket[req_group_key] = []
                    end
                    @requests_bucket[req_group_key].push(request)
                  end

                  if @scheduled_tasks[req_group_key].nil?
                    @scheduled_tasks[req_group_key] = TaskWithTimestamp.new(
                      req_group_key,
                      @requests_bucket,
                      @requests_bucket_mutex,
                      @batch_waiting_time,
                      @batching_queue
                    )
                  else
                    # http://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/ScheduledTask.html#reschedule-instance_method
                    reset_result = @scheduled_tasks[req_group_key].task.reset
                    if !reset_result
                      @scheduled_tasks[req_group_key] = TaskWithTimestamp.new(
                        req_group_key,
                        @requests_bucket,
                        @requests_bucket_mutex,
                        @batch_waiting_time,
                        @batching_queue
                      )
                    end
                  end
                elsif !@raw_request_queue.closed?
                  raise "the request is nil but raw_request_queue not closed." 
                else
                  break
                end
              end
            end
            thread.abort_on_exception = true
          end
        end
      end
    end
  end
end
