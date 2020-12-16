describe Calyx::Syntax::Memo do
  it 'uses the registry to memoize expansions' do
    registry = double('registry')
    allow(registry).to receive(:memoize_expansion).with(:one).and_return('ONE')
    memo = Calyx::Syntax::Memo.new(:@one, registry)
    expect(memo.evaluate(Calyx::Options.new)).to eq([:one, 'ONE'])
  end
end
