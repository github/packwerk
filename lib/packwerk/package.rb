# typed: strict
# frozen_string_literal: true

module Packwerk
  # The basic unit of modularity for packwerk; a folder that has been declared to define a package.
  # The package contains all constants defined in files in this folder and all subfolders that are not packages
  # themselves.
  class Package
    extend T::Sig
    include Comparable

    ROOT_PACKAGE_NAME = "."

    sig { returns(String) }
    attr_reader :name
    sig { returns(T::Array[String]) }
    attr_reader :dependencies

    class << self
      extend T::Sig

      sig { params(path: Pathname, root_path: String).returns(Package) }
      def from_path(path:, root_path:)
        config = YAML.load_file(path)
        dep_ref_path = File.join(File.dirname(path), "deprecated_references.yml")
        deprecated_references = Packwerk::DeprecatedReferences.from_path(dep_ref_path)
        name = path.dirname.relative_path_from(root_path).to_s

        new(name: name, config: config, deprecated_references: deprecated_references)
      end
    end

    sig do
      params(
        name: String,
        config: T.nilable(T.any(T::Hash[T.untyped, T.untyped], FalseClass)),
        deprecated_references: Packwerk::DeprecatedReferences
      ).void
    end
    def initialize(name:, config:, deprecated_references: DeprecatedReferences.new)
      @name = name
      @config = T.let(config || {}, T::Hash[T.untyped, T.untyped])
      @dependencies = T.let(Array(@config["dependencies"]).freeze, T::Array[String])
      @public_path = T.let(nil, T.nilable(String))
      @deprecated_references = deprecated_references
    end

    sig { returns(T.nilable(T.any(T::Boolean, T::Array[String]))) }
    def enforce_privacy
      @config["enforce_privacy"]
    end

    sig { returns(T::Boolean) }
    def enforce_dependencies?
      @config["enforce_dependencies"] == true
    end

    sig { params(package: Package).returns(T::Boolean) }
    def dependency?(package)
      @dependencies.include?(package.name)
    end

    sig { params(path: String).returns(T::Boolean) }
    def package_path?(path)
      return true if root?
      path.start_with?(@name)
    end

    sig { returns(String) }
    def public_path
      @public_path ||= begin
        unprefixed_public_path = user_defined_public_path || "app/public/"

        if root?
          unprefixed_public_path
        else
          File.join(@name, unprefixed_public_path)
        end
      end
    end

    sig { params(path: String).returns(T::Boolean) }
    def public_path?(path)
      path.start_with?(public_path)
    end

    sig { returns(T.nilable(String)) }
    def user_defined_public_path
      return unless @config["public_path"]
      return @config["public_path"] if @config["public_path"].end_with?("/")

      @config["public_path"] + "/"
    end

    sig { params(other: T.untyped).returns(T.nilable(Integer)) }
    def <=>(other)
      return nil unless other.is_a?(self.class)
      name <=> other.name
    end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def eql?(other)
      self == other
    end

    sig { returns(Integer) }
    def hash
      name.hash
    end

    sig { returns(String) }
    def to_s
      name
    end

    sig { returns(T::Boolean) }
    def root?
      @name == ROOT_PACKAGE_NAME
    end

    sig { returns(Packwerk::DeprecatedReferences) }
    attr_reader :deprecated_references
  end
end
