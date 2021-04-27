# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "benchmark"

require "packwerk/commands/offense_progress_marker"
require "packwerk/commands/result"
require "packwerk/run_context"
require "packwerk/updating_deprecated_references"

module Packwerk
  module Commands
    class UpdateDeprecationsCommand
      extend T::Sig
      include OffenseProgressMarker

      sig do
        params(
          files: T::Enumerable[String],
          configuration: Configuration,
          offenses_formatter: Formatters::OffensesFormatter,
          progress_formatter: Formatters::ProgressFormatter
        ).void
      end
      def initialize(files:, configuration:, offenses_formatter:, progress_formatter:)
        @files = files
        @configuration = configuration
        @progress_formatter = progress_formatter
        @offenses_formatter = offenses_formatter
        @run_context = T.let(nil, T.nilable(RunContext))
      end

      sig { returns(Result) }
      def run
        @progress_formatter.started(@files)
        execution_time = Benchmark.realtime do
          all_offenses = @files.flat_map do |path|
            run_context.process_file(file: path).tap do |offenses|
              mark_progress(offenses: offenses, progress_formatter: @progress_formatter)
            end
          end

          updating_deprecated_references ||= UpdatingDeprecatedReferences.new(@configuration.root_path)
          all_offenses.each do |offense|
            next unless offense.respond_to?(:reference)
            updating_deprecated_references.listed?(offense.reference, violation_type: offense.violation_type)
          end

          updating_deprecated_references.dump_deprecated_references_files
        end

        @progress_formatter.finished(execution_time)
        Result.new(message: "✅ `deprecated_references.yml` has been updated.", status: true)
      end

      private

      sig { returns(RunContext) }
      def run_context
        @run_context ||= RunContext.from_configuration(@configuration)
      end
    end
  end
end
