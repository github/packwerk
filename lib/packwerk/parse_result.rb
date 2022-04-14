# typed: strict
# frozen_string_literal: true

module Packwerk
  class ParseResult
    extend T::Sig
    extend T::Helpers

    sig { params(package_set: Packwerk::PackageSet).void }
    def initialize(package_set)
      @package_set = T.let(Set.new(package_set), T::Set[Packwerk::Package])
      @new_violations = T.let([], T::Array[Packwerk::ReferenceOffense])
      @errors = T.let([], T::Array[Packwerk::Offense])
    end

    sig { returns(T::Array[Packwerk::ReferenceOffense]) }
    attr_reader :new_violations

    sig { returns(T::Array[Packwerk::Offense]) }
    attr_reader :errors

    sig do
      params(offense: Packwerk::Offense)
        .returns(T::Boolean)
    end
    def listed?(offense)
      return false unless offense.is_a?(ReferenceOffense)

      reference = offense.reference
      package = reference.source_package
      raise "Unknown package #{package.name}" unless @package_set.include?(package)

      package.deprecated_references.listed?(reference, violation_type: offense.violation_type)
    end

    sig do
      params(offense: Packwerk::Offense).void
    end
    def add_offense(offense)
      unless offense.is_a?(ReferenceOffense)
        @errors << offense
        return
      end
      deprecated_references = offense.reference.source_package.deprecated_references
      unless deprecated_references.add_entries(offense.reference, offense.violation_type)
        new_violations << offense
      end
    end

    sig { returns(T::Boolean) }
    def stale_violations?
      @package_set.any? { |package| package.deprecated_references.stale_violations? }
    end

    sig { params(root_path: String).void }
    def dump_deprecated_references_files(root_path)
      @package_set.each do |package|
        path = File.join(root_path, package.name, "deprecated_references.yml")
        package.deprecated_references.dump(file_path: path, package: package)
      end
    end

    sig { returns(T::Array[Packwerk::Offense]) }
    def outstanding_offenses
      errors + new_violations
    end
  end
end
