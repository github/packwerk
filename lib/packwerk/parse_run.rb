# typed: strict
# frozen_string_literal: true

require "benchmark"
require "parallel"

module Packwerk
  class ParseRun
    extend T::Sig

    ProcessFileProc = T.type_alias do
      T.proc.params(path: String).returns(T::Array[Offense])
    end

    sig do
      params(
        absolute_files: T::Array[String],
        configuration: Configuration,
        progress_formatter: Formatters::ProgressFormatter,
        offenses_formatter: OffensesFormatter,
      ).void
    end
    def initialize(
      absolute_files:,
      configuration:,
      progress_formatter: Formatters::ProgressFormatter.new(StringIO.new),
      offenses_formatter: Formatters::OffensesFormatter.new
    )
      @configuration = configuration
      @progress_formatter = progress_formatter
      @offenses_formatter = offenses_formatter
      @absolute_files = absolute_files
      @run_context = T.let(Packwerk::RunContext.from_configuration(@configuration), Packwerk::RunContext)
    end

    sig { returns(Result) }
    def detect_stale_violations
      parse_result = find_offenses

      result_status = !parse_result.stale_violations?
      message = @offenses_formatter.show_stale_violations(parse_result)

      Result.new(message: message, status: result_status)
    end

    sig { returns(Result) }
    def update_deprecations
      parse_result = find_offenses

      @run_context.package_set.each do |package|
        path = File.join(package.name, "deprecated_references.yml")
        File.delete(path) if File.exist?(path)
      end

      parse_result.dump_deprecated_references_files(@configuration.root_path)

      message = <<~EOS
        #{@offenses_formatter.show_offenses(parse_result.errors)}
        ✅ `deprecated_references.yml` has been updated.
      EOS

      Result.new(message: message, status: parse_result.errors.empty?)
    end

    sig { returns(Result) }
    def check
      parse_result = find_offenses(show_errors: true)

      messages = [
        @offenses_formatter.show_offenses(parse_result.outstanding_offenses),
        @offenses_formatter.show_stale_violations(parse_result),
      ]
      result_status = parse_result.outstanding_offenses.empty? && !parse_result.stale_violations?

      Result.new(message: messages.join("\n") + "\n", status: result_status)
    end

    private

    sig { params(show_errors: T::Boolean).returns(ParseResult) }
    def find_offenses(show_errors: false)
      parse_result = ParseResult.new(@run_context.package_set)
      @progress_formatter.started(@absolute_files)

      all_offenses = T.let([], T::Array[Offense])

      process_file = T.let(-> (absolute_file) do
        @run_context.process_file(absolute_file: absolute_file).tap do |offenses|
          failed = show_errors && offenses.any? { |offense| !parse_result.listed?(offense) }
          update_progress(failed: failed)
        end
      end, ProcessFileProc)

      execution_time = Benchmark.realtime do
        all_offenses = if @configuration.parallel?
          Parallel.flat_map(@absolute_files, &process_file)
        else
          serial_find_offenses(&process_file)
        end
      end

      @progress_formatter.finished(execution_time)

      all_offenses.each { |offense| parse_result.add_offense(offense) }
      parse_result
    end

    sig { params(block: ProcessFileProc).returns(T::Array[Offense]) }
    def serial_find_offenses(&block)
      all_offenses = T.let([], T::Array[Offense])
      begin
        @absolute_files.each do |absolute_file|
          offenses = block.call(absolute_file)
          all_offenses.concat(offenses)
        end
      rescue Interrupt
        @progress_formatter.interrupted
        all_offenses
      end
      all_offenses
    end

    sig { params(failed: T::Boolean).void }
    def update_progress(failed: false)
      if failed
        @progress_formatter.mark_as_failed
      else
        @progress_formatter.mark_as_inspected
      end
    end
  end
end
