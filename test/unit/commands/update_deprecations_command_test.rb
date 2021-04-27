# frozen_string_literal: true
require "test_helper"
require "rails_test_helper"
require "packwerk/commands/update_deprecations_command"

module Packwerk
  module Commands
    class UpdateDeprecationsCommandTest < Minitest::Test
      test "#run returns success" do
        stub_offenses([])
        result = update_deprecations_command.run

        assert_equal "✅ `deprecated_references.yml` has been updated.", result.message
        assert result.status
      end

      test "#run ignores non-reference offenses" do
        stub_offenses([Offense.new(message: "foo", file: "path/of/exile.rb")])
        UpdatingDeprecatedReferences.any_instance.expects(:listed?).never
        UpdatingDeprecatedReferences.any_instance.expects(:dump_deprecated_references_files).once

        update_deprecations_command.run
      end

      test "#run adds reference offenses" do
        source_package = Package.new(name: "components/sales", config: { "enforce_dependencies" => true })
        reference =
          Reference.new(
            source_package,
            "path/of/exile.rb",
            ConstantDiscovery::ConstantContext.new(
              "::SomeName",
              "some/location.rb",
              nil,
              false
            )
          )
        offense = ReferenceOffense.new(reference: reference, violation_type: ViolationType::Dependency)
        stub_offenses([offense])
        UpdatingDeprecatedReferences.any_instance.expects(:listed?).once.with(reference, violation_type: ViolationType::Dependency)
        UpdatingDeprecatedReferences.any_instance.expects(:dump_deprecated_references_files).once

        update_deprecations_command.run
      end

      private

      def stub_offenses(offenses)
        run_context = RunContext.new(root_path: ".", load_paths: ".")
        run_context.stubs(:process_file).returns(offenses)
        RunContext.stubs(from_configuration: run_context)
      end

      def update_deprecations_command
        Commands::UpdateDeprecationsCommand.new(
          configuration: Configuration.from_path,
          files: ["path/of/exile.rb"],
          offenses_formatter: Formatters::OffensesFormatter.new,
          progress_formatter: Formatters::ProgressFormatter.new(StringIO.new),
        )
      end
    end
  end
end
