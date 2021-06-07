require 'spec_helper'

PrefixNode = Struct.new(:children, :index)
PrefixEdge = Struct.new(:node, :label, :wildcard?)
PrefixMatch = Struct.new(:label, :index, :captured)

class PrefixTree
  def initialize
    @root = PrefixNode.new([], nil)
  end

  def insert(label, index)
    if @root.children.empty?
      @root.children << PrefixEdge.new(PrefixNode.new([], index), label, false)
    end
  end

  def add_all(elements)
    elements.each_with_index { |el, i| add(el, i) }
  end

  def add(label, index)
    parts = label.split(/(%)/).reject { |p| p.empty? }
    parts_count = parts.count

    # Can’t use more than one capture symbol which gives the following splits:
    # - ["literal"]
    # - ["%", "literal"]
    # - ["literal", "%"]
    # - ["literal", "%", "literal"]
    if parts_count > 3
      raise "Too many capture patterns: #{label}"
    end

    current_node = @root

    parts.each_with_index do |part, i|
      index_slot = (i == parts_count - 1) ? index : nil
      is_wildcard = part == "%"
      matched_prefix = false

      current_node.children.each_with_index do |edge, j|
        prefix = common_prefix(edge.label, part)
        unless prefix.empty?
          matched_prefix = true

          if prefix == edge.label
            # Current prefix matches the edge label so we can continue down the
            # tree without mutating the current branch
            next_node = PrefixNode.new([], index_slot)
            current_node.children << PrefixEdge.new(next_node, label.delete_prefix(prefix), is_wildcard)
          else
            # We have a partial match on current edge so replace it with the new
            # prefix then rejoin the remaining suffix to the existing branch
            edge.label = edge.label.delete_prefix(prefix)
            prefix_node = PrefixNode.new([edge], nil)
            next_node = PrefixNode.new([], index_slot)
            prefix_node.children << PrefixEdge.new(next_node, label.delete_prefix(prefix), is_wildcard)
            current_node.children[j] = PrefixEdge.new(prefix_node, prefix, is_wildcard)
          end

          current_node = next_node
          break
        end
      end

      # No existing edges have a common prefix so push a new branch onto the tree
      # at the current level
      unless matched_prefix
        next_edge = PrefixEdge.new(PrefixNode.new([], index_slot), part, is_wildcard)
        current_node.children << next_edge
        current_node = next_edge.node
      end
    end
  end

  def insert_string_trie
    add("test", 2)
    add("team", 3)
    #st = PrefixEdge.new(PrefixNode.new([], 2), "st", false)
    #am = PrefixEdge.new(PrefixNode.new([], 3), "am", false)
    #@root.children << PrefixEdge.new(PrefixNode.new([am, st], 1), "te", false)
  end

  def insert_leading_wildcard_trie
    add("%es", 111)
    #es = PrefixEdge.new(PrefixNode.new([], 111), "es", false)
    #@root.children << PrefixEdge.new(PrefixNode.new([es], 1), "%", true)
  end

  def insert_trailing_wildcard_trie
    add("te%", 222)
    #wildcard = PrefixEdge.new(PrefixNode.new([], 222), "%", true)
    #@root.children << PrefixEdge.new(PrefixNode.new([wildcard], 1), "te", false)
  end

  def insert_anchored_wildcard_trie
    add("te%s", 333)
    #plural_suffix = PrefixEdge.new(PrefixNode.new([], 333), "s", false)
    #wildcard = PrefixEdge.new(PrefixNode.new([plural_suffix], 222), "%", true)
    #@root.children << PrefixEdge.new(PrefixNode.new([wildcard], 1), "te", false)
  end

  def insert_catch_all_wildcard_trie
    add("%", 444)
    #@root.children << PrefixEdge.new(PrefixNode.new([], 444), "%", true)
  end

  def insert_cascading_wildcard_trie
    add("%y", 555)
    add("%s", 666)
    add("%", 444)
    #y = PrefixEdge.new(PrefixNode.new([], 555), "y", false)
    #s = PrefixEdge.new(PrefixNode.new([], 666), "s", false)
    #_ = PrefixEdge.new(PrefixNode.new([], 444), "", false)
    #@root.children << PrefixEdge.new(PrefixNode.new([y, s, _], 444), "%", true)
  end

  # This was basically ported from the pseudocode found on Wikipedia to Ruby,
  # with a lot of extra internal state tracking that is totally absent from
  # most algorithmic descriptions. This ends up making a real mess of the
  # expression of the algorithm, mostly due to choices and conflicts between
  # whether to go with the standard iterative and procedural flow of statements
  # or use a more functional style. A mangle that speaks to the questions
  # around portability between different languages. Is this codebase a design
  # prototype? Is it an evolving example that should guide implementations in
  # other languages?
  #
  # The problem with code like this is that it’s a bit of a maintenance burden
  # if not structured compactly and precisely enough to not matter and having
  # enough tests passing that it lasts for a few years without becoming a
  # nuisance or leading to too much nonsense.
  #
  # There are several ways to implement this, some of these may work better or
  # worse, and this might be quite different across multiple languages so what
  # goes well in one place could suck in other places. The only way to make a
  # good decision around it is to learn via testing and experiments.
  #
  # Alternative possible implementations:
  # - Regex compilation on registration, use existing legacy mapping code
  # - Prefix tree, trie, radix tree/trie, compressed bitpatterns, etc
  # - Split string flip, imperative list processing hacks
  #   (easier for more people to contribute?)
  def lookup(label)
    current_node = @root
    chars_consumed = 0
    chars_captured = nil
    label_length = label.length

    # Traverse the tree until reaching a leaf node or all input characters are consumed
    while current_node != nil && !current_node.children.empty? && chars_consumed < label_length
      # Candidate edge pointing to the next node to check
      candidate_edge = nil

      # Traverse from the current node down the tree looking for candidate edges
      current_node.children.each do |edge|
        # Generate a suffix based on the prefix already consumed
        sub_label = label[chars_consumed, label_length]

        # If this edge is a wildcard we check the next level of the tree
        if edge.wildcard?
          # Wildcard pattern is anchored to the end of the string so we can
          # consume all remaining characters and pick this as an edge candidate
          if edge.node.children.empty?
            chars_captured = label[chars_consumed, sub_label.length]
            chars_consumed += sub_label.length
            candidate_edge = edge
            break
          end

          # The wildcard is anchored to the start or embedded in the middle of
          # the string so we traverse this edge and scan the next level of the
          # tree with a greedy lookahead. This means we will always match as
          # much of the wildcard string as possible when there is a trailing
          # suffix that could be repeated several times within the characters
          # consumed by the wildcard pattern.
          #
          # For example, we expect `"te%s"` to match on `"tests"` rather than
          # bail out after matching the first three characters `"tes"`.
          edge.node.children.each do |lookahead_edge|
            prefix = sub_label.rindex(lookahead_edge.label)
            if prefix
              chars_captured = label[chars_consumed, prefix]
              chars_consumed += prefix + lookahead_edge.label.length
              candidate_edge = lookahead_edge
              break
            end
          end
          # We found a candidate so no need to continue checking edges
          break if candidate_edge
        else
          # Look for a common prefix on this current edge label and the remaining suffix
          if edge.label == common_prefix(edge.label, sub_label)
            chars_consumed += edge.label.length
            candidate_edge = edge
            break
          end
        end
      end

      if candidate_edge
        # Traverse to the node our edge candidate points to
        current_node = candidate_edge.node
      else
        # We didn’t find a possible edge candidate so bail out of the loop
        current_node = nil
      end
    end

    # In order to return a match, the following postconditions must be true:
    # - We are pointing to a leaf node
    # - We have consumed all the input characters
    if current_node != nil and current_node.index != nil and chars_consumed == label_length
      PrefixMatch.new(label, current_node.index, chars_captured)
    else
      nil
    end
  end

  def common_prefix(a, b)
    selected_prefix = ""
    min_index_length = a < b ? a.length : b.length
    index = 0

    until index == min_index_length
      return selected_prefix if a[index] != b[index]
      selected_prefix += a[index]
      index += 1
    end

    selected_prefix
  end
end

describe Calyx::Syntax::PairedMapping do
  let(:registry) do
    Calyx::Registry.new
  end

  describe 'literal match' do
    let(:paired_map) do
      Calyx::Syntax::PairedMapping.parse({
        'atom' => 'atoms',
        'molecule' => 'molecules'
      }, registry)
    end

    specify 'lookup from key to value' do
      expect(paired_map.value_for('atom')).to eq('atoms')
      expect(paired_map.value_for('molecule')).to eq('molecules')
    end

    specify 'lookup from value to key' do
      expect(paired_map.key_for('atoms')).to eq('atom')
      expect(paired_map.key_for('molecules')).to eq('molecule')
    end
  end

  describe 'wildcard match' do
    let(:paired_map) do
      Calyx::Syntax::PairedMapping.parse({
        "%y" => "%ies",
        "%s" => "%ses",
        "%" => "%s"
      }, registry)
    end

    specify 'lookup from key to value' do
      expect(paired_map.value_for('ferry')).to eq('ferries')
      expect(paired_map.value_for('bus')).to eq('buses')
      expect(paired_map.value_for('car')).to eq('cars')
    end

    specify 'lookup from value to key' do
      expect(paired_map.key_for('ferries')).to eq('ferry')
      expect(paired_map.key_for('buses')).to eq('bus')
      expect(paired_map.key_for('cars')).to eq('car')
    end
  end

  describe 'trie or radix tree' do
    specify 'longest common prefix of strings' do
      tree = PrefixTree.new
      expect(tree.common_prefix("a", "b")).to eq("")
      expect(tree.common_prefix("aaaaa", "aab")).to eq("aa")
      expect(tree.common_prefix("aa", "ab")).to eq("a")
      expect(tree.common_prefix("ababababahahahaha", "ababafgfgbaba")).to eq("ababa")
    end

    specify "insert single value" do
      tree = PrefixTree.new
      tree.insert("one", 0)

      expect(tree.lookup("one").index).to eq(0)
      expect(tree.lookup("one!!")).to be_falsey
      expect(tree.lookup("two")).to be_falsey
    end

    specify "lookup with literal string data" do
      tree = PrefixTree.new
      tree.insert_string_trie

      expect(tree.lookup("test").index).to eq(2)
      expect(tree.lookup("team").index).to eq(3)
      expect(tree.lookup("teal")).to be_falsey
    end

    specify "lookup with leading wildcard data" do
      tree = PrefixTree.new
      tree.insert_leading_wildcard_trie

      expect(tree.lookup("buses").index).to eq(111)
      expect(tree.lookup("bus")).to be_falsey
      expect(tree.lookup("train")).to be_falsey
      expect(tree.lookup("bushes").index).to eq(111)
    end

    specify "lookup with trailing wildcard data" do
      tree = PrefixTree.new
      tree.insert_trailing_wildcard_trie

      expect(tree.lookup("test").index).to eq(222)
      expect(tree.lookup("total")).to be_falsey
      expect(tree.lookup("rubbish")).to be_falsey
      expect(tree.lookup("team").index).to eq(222)
    end

    specify "lookup with anchored wildcard data" do
      tree = PrefixTree.new
      tree.insert_anchored_wildcard_trie

      expect(tree.lookup("tests").index).to eq(333)
      expect(tree.lookup("total")).to be_falsey
      expect(tree.lookup("test")).to be_falsey
      expect(tree.lookup("team")).to be_falsey
      expect(tree.lookup("teams").index).to eq(333)
    end

    specify "lookup with anchored wildcard data" do
      tree = PrefixTree.new
      tree.insert_catch_all_wildcard_trie

      expect(tree.lookup("tests").index).to eq(444)
      expect(tree.lookup("total").index).to eq(444)
      expect(tree.lookup("test").index).to eq(444)
      expect(tree.lookup("team").index).to eq(444)
      expect(tree.lookup("teams").index).to eq(444)
    end

    specify "lookup with anchored wildcard data" do
      tree = PrefixTree.new
      tree.insert_cascading_wildcard_trie

      expect(tree.lookup("ferry").index).to eq(555)
      expect(tree.lookup("bus").index).to eq(666)
      expect(tree.lookup("car").index).to eq(444)
    end
  end
end