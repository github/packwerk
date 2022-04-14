# typed: strict
# frozen_string_literal: true

require "benchmark"
require "parallel"

module Packwerk
  class ParseRun
    extend T::Sig

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
      @progress_formatter = progress_formatter
      @offenses_formatter = offenses_formatter
      @file_count = T.let(absolute_files.count, Integer)
      @offense_collector = T.let(OffenseCollector.new(
        absolute_files: absolute_files,
        run_context: RunContext.from_configuration(configuration)
      ), Packwerk::OffenseCollector)
    end

    sig { returns(Result) }
    def detect_stale_violations
      offense_collection = find_offenses

      result_status = !offense_collection.stale_violations?
      message = @offenses_formatter.show_stale_violations(offense_collection)

      Result.new(message: message, status: result_status)
    end

    sig { returns(Result) }
    def update_deprecations
      offense_collection = find_offenses
      offense_collection.dump_deprecated_references_files

      message = <<~EOS
        #{@offenses_formatter.show_offenses(offense_collection.errors)}
        ✅ `deprecated_references.yml` has been updated.
      EOS

      Result.new(message: message, status: offense_collection.errors.empty?)
    end

    sig { returns(Result) }
    def check
      offense_collection = find_offenses(show_errors: true)

      messages = [
        @offenses_formatter.show_offenses(offense_collection.outstanding_offenses),
        @offenses_formatter.show_stale_violations(offense_collection),
      ]
      result_status = offense_collection.outstanding_offenses.empty? && !offense_collection.stale_violations?

      Result.new(message: messages.join("\n") + "\n", status: result_status)
    end

    private

    sig { params(show_errors: T::Boolean).returns(OffenseCollection) }
    def find_offenses(show_errors: true)
      offense_collection = T.let(nil, T.nilable(OffenseCollection))
      @progress_formatter.started(@file_count)

      execution_time = Benchmark.realtime do
        offense_collection = @offense_collector.find_offenses do |_, success|
          next unless show_errors

          if success
            @progress_formatter.mark_as_inspected
          else
            @progress_formatter.mark_as_failed
          end
        end

        @progress_formatter.interrupted if offense_collection.interrupted?
      end

      @progress_formatter.finished(execution_time)

      T.must(offense_collection)
    end
  end
end
