# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "packwerk/reference_lister"

module Packwerk
  module Checker
    extend T::Sig
    extend T::Helpers

    interface!

    sig { returns(ViolationType).abstract }
    def violation_type; end

    sig { params(reference: Reference).returns(T::Boolean).abstract }
    def invalid_reference?(reference); end
  end
end
