# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Packwerk
  module OffensesFormatter
    extend T::Sig
    extend T::Helpers

    interface!

    sig { params(offenses: T::Array[T.nilable(Offense)]).returns(String) }
    def show_offenses(offenses)
    end
  end
end
