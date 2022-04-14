# typed: strict
# frozen_string_literal: true

module Packwerk
  class OffenseCollector
    extend T::Sig

    ReportProgressProc = T.type_alias do
      T.proc.params(path: String, success: T::Boolean).void
    end

    sig { params(absolute_files: T::Array[String], run_context: RunContext).void }
    def initialize(absolute_files:, run_context:)
      @absolute_files = absolute_files
      @run_context = run_context
    end

    sig { params(progress_block: ReportProgressProc).returns(OffenseCollection) }
    def find_offenses(&progress_block)
      if run_context.parallel?
        parallel_find_offenses(&progress_block)
      else
        serial_find_offenses(&progress_block)
      end
    end

    private

    sig { params(progress_block: ReportProgressProc).returns(OffenseCollection) }
    def parallel_find_offenses(&progress_block)
      offense_collection = OffenseCollection.new(@run_context.root_path)

      all_offenses = Parallel.flat_map(@absolute_files) do |absolute_file|
        process_file(absolute_file: absolute_file, deprecated_offenses: offense_collection, &progress_block)
      end

      all_offenses.each { |offense| offense_collection.add_offense(offense) }
      offense_collection
    end

    sig { params(progress_block: ReportProgressProc).returns(Packwerk::OffenseCollection) }
    def serial_find_offenses(&progress_block)
      offense_collection = OffenseCollection.new(@run_context.root_path)
      begin
        @absolute_files.flat_map do |absolute_file|
          process_file(absolute_file: absolute_file, deprecated_offenses: offense_collection, &progress_block).each do |offense|
            offense_collection.add_offense(offense)
          end
        end
      rescue
        offense_collection.interrupted!
        offense_collection
      end
    end

    sig do
      params(
        absolute_file: String,
        deprecated_offenses: Packwerk::OffenseCollection,
        progress_block: ReportProgressProc
      ).returns(T::Array[Packwerk::Offense])
    end
    def process_file(absolute_file:, deprecated_offenses:, &progress_block)
      offenses = parse_offenses(absolute_file: absolute_file)
      failed = offenses.any? { |offense| !deprecated_offenses.listed?(offense) }
      progress_block.call(absolute_file, failed)
      offenses
    end

    sig { params(absolute_file: String).returns(T::Array[Packwerk::Offense]) }
    def parse_offenses(absolute_file:)
      unresolved_references_and_offenses = @run_context.file_processor.call(absolute_file)
      references_and_offenses = ReferenceExtractor.get_fully_qualified_references_and_offenses_from(
        unresolved_references_and_offenses,
        @run_context.context_provider
      )

      reference_checker = ReferenceChecking::ReferenceChecker.new(@run_context.checkers)
      references_and_offenses.flat_map { |reference| reference_checker.call(reference) }
    end
  end
end
