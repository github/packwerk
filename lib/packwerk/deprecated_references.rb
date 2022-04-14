# typed: strict
# frozen_string_literal: true

require "yaml"

module Packwerk
  class DeprecatedReferences
    extend T::Sig

    ENTRIES_TYPE = T.type_alias do
      T::Hash[String, T.untyped]
    end

    class << self
      extend T::Sig

      sig { params(path: String).returns(DeprecatedReferences) }
      def from_path(path)
        dep_ref_data = begin
          YAML.load_file(path)
        rescue StandardError
          {}
        end
        dep_ref_data = {} unless dep_ref_data.is_a?(Hash)
        new(dep_ref_data)
      end
    end

    sig { params(data: ENTRIES_TYPE).void }
    def initialize(data = {})
      @new_entries = T.let({}, ENTRIES_TYPE)
      @deprecated_references = T.let(data, ENTRIES_TYPE)
    end

    sig do
      params(reference: Packwerk::Reference, violation_type: ViolationType)
        .returns(T::Boolean)
    end
    def listed?(reference, violation_type:)
      violated_constants_found = @deprecated_references.dig(reference.constant.package.name, reference.constant.name)
      return false unless violated_constants_found

      violated_constant_in_file = violated_constants_found.fetch("files", []).include?(reference.relative_path)
      return false unless violated_constant_in_file

      violated_constants_found.fetch("violations", []).include?(violation_type.serialize)
    end

    sig { params(reference: Packwerk::Reference, violation_type: Packwerk::ViolationType).returns(T::Boolean) }
    def add_entries(reference, violation_type)
      package_violations = @new_entries.fetch(reference.constant.package.name, {})
      entries_for_file = package_violations[reference.constant.name] ||= {}

      entries_for_file["violations"] ||= []
      entries_for_file["violations"] << violation_type.serialize

      entries_for_file["files"] ||= []
      entries_for_file["files"] << reference.relative_path.to_s

      @new_entries[reference.constant.package.name] = package_violations
      listed?(reference, violation_type: violation_type)
    end

    sig { returns(T::Boolean) }
    def stale_violations?
      prepare_entries_for_dump
      @deprecated_references.any? do |package, package_violations|
        package_violations.any? do |constant_name, entries_for_file|
          new_entries_violation_types = @new_entries.dig(package, constant_name, "violations")
          return true if new_entries_violation_types.nil?
          if entries_for_file["violations"].all? { |type| new_entries_violation_types.include?(type) }
            stale_violations =
              entries_for_file["files"] - Array(@new_entries.dig(package, constant_name, "files"))
            stale_violations.any?
          else
            return true
          end
        end
      end
    end

    sig { params(file_path: String, package: T.nilable(Packwerk::Package)).void }
    def dump(file_path:, package: nil)
      package_name = package.nil? ? "this package" : package.name

      if @new_entries.empty?
        File.delete(file_path) if File.exist?(file_path)
      else
        prepare_entries_for_dump
        message = <<~MESSAGE
          # This file contains a list of dependencies that are not part of the long term plan for #{package_name}.
          # We should generally work to reduce this list, but not at the expense of actually getting work done.
          #
          # You can regenerate this file using the following command:
          #
          # bin/packwerk update-deprecations #{package_name}
        MESSAGE
        File.open(file_path, "w") do |f|
          f.write(message)
          f.write(@new_entries.to_yaml)
        end
      end
    end

    private

    sig { returns(ENTRIES_TYPE) }
    def prepare_entries_for_dump
      @new_entries.each do |package_name, package_violations|
        package_violations.each do |_, entries_for_file|
          entries_for_file["violations"].sort!.uniq!
          entries_for_file["files"].sort!.uniq!
        end
        @new_entries[package_name] = package_violations.sort.to_h
      end

      @new_entries = @new_entries.sort.to_h
    end
  end
end
