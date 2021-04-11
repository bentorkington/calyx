module Calyx
  # Applies modifiers to the output of a rule in a template substitution.
  class Modifiers
    # Transforms an output string by delegating to the given output function.
    #
    # If a registered modifier method is not found, then delegate to the given
    # string function.
    #
    # If an invalid modifier function is given, returns the raw input string.
    #
    # @param [Symbol] name
    # @param [String] value
    # @return [String]
    def transform(name, value)
      if respond_to?(name)
        send(name, value)
      elsif value.respond_to?(name)
        value.send(name)
      else
        value
      end
    end

    def upper(value)
      value.upcase
    end

    def lower(value)
      value.downcase
    end
  end
end
