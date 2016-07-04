module Calyx
  module Format
    def self.load(filename)
      file = File.read(filename)
      extension = File.extname(filename)
      if extension == ".yml"
        self.load_yml(file)
      elsif extension == ".json"
        self.load_json(file)
      else
        raise "Cannot convert #{extension} files."
      end
    end

    def self.load_yml(data)
      require 'yaml'
      self.build_grammar(YAML.load(data))
    end

    def self.load_json(data)
      require 'json'
      self.build_grammar(JSON.parse(data))
    end

    private

    def self.build_grammar(rules)
      Calyx::Grammar.new do
        rules.each do |label, productions|
          rule(label, *productions)
        end
      end
    end
  end
end
