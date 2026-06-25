require 'helper'
require 'lmdb'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'LMDB GC safety' do
  let(:env)  { LMDB.new(path, mapsize: 2**24) }
  let(:db)   { env.database('test', create: true) }

  before(:each) { db }  # open db before each example

  after(:each) do
    env.close rescue nil
    FileUtils.rm_rf path
  end

  # -----------------------------------------------------------------------
  # 1. Basic GC.compact safety — no open transactions
  #    Verifies compaction callbacks update all VALUE references correctly
  # -----------------------------------------------------------------------
  it 'survives GC.compact with no open transactions' do
    env.transaction { db['key'] = 'value' }
    expect { GC.compact }.not_to raise_error
    env.transaction(true) { expect(db['key']).to eq 'value' }
  end

  # -----------------------------------------------------------------------
  # 2. GC.compact during an open read transaction
  #    Verifies the transaction object survives compaction
  # -----------------------------------------------------------------------
  it 'survives GC.compact with an open read transaction' do
    env.transaction { db['key'] = 'value' }
    env.transaction(true) do |txn|
      expect { GC.compact }.not_to raise_error
      expect(db['key']).to eq 'value'
      expect(txn.finished?).to be false
    end
  end

  # -----------------------------------------------------------------------
  # 3. GC.compact between consecutive write transactions
  #    This is the Store::Digest scenario — write, compact, write again
  # -----------------------------------------------------------------------
  it 'allows a new write transaction after GC.compact' do
    env.transaction { db['key1'] = 'value1' }
    GC.compact
    expect {
      env.transaction { db['key2'] = 'value2' }
    }.not_to raise_error
    env.transaction(true) do
      expect(db['key1']).to eq 'value1'
      expect(db['key2']).to eq 'value2'
    end
  end

  # -----------------------------------------------------------------------
  # 4. GC.compact after multiple write transactions
  #    Stress version — compact after several writes
  # -----------------------------------------------------------------------
  it 'allows write transactions after repeated GC.compact calls' do
    5.times do |i|
      env.transaction { db["key#{i}"] = "value#{i}" }
      GC.compact
    end
    env.transaction(true) do
      5.times do |i|
        expect(db["key#{i}"]).to eq "value#{i}"
      end
    end
  end

  # -----------------------------------------------------------------------
  # 5. GC.compact with a pseudo-transaction (RO nested in RW)
  #    Verifies pseudo-transaction compaction safety
  # -----------------------------------------------------------------------
  it 'survives GC.compact after pseudo-transaction use' do
    env.transaction do
      db['key'] = 'value'
      env.transaction(true) do
        expect(db['key']).to eq 'value'
      end
    end
    GC.compact
    expect {
      env.transaction { db['key2'] = 'value2' }
    }.not_to raise_error
  end

  # -----------------------------------------------------------------------
  # 6. GC.compact with cursor use
  #    Verifies cursor compaction safety
  # -----------------------------------------------------------------------
  it 'survives GC.compact after cursor iteration' do
    env.transaction do
      5.times { |i| db["key#{i}"] = "value#{i}" }
    end
    env.transaction(true) do
      db.cursor do |c|
        c.first
        GC.compact
        expect(c.next).not_to be_nil
      end
    end
    GC.compact
    expect {
      env.transaction { db['new'] = 'write' }
    }.not_to raise_error
  end

  # -----------------------------------------------------------------------
  # 7. GC.start (sweep without compaction) — baseline
  #    Should always pass; establishes that non-compacting GC is safe
  # -----------------------------------------------------------------------
  it 'survives GC.start (sweep only) between write transactions' do
    env.transaction { db['key1'] = 'value1' }
    GC.start
    expect {
      env.transaction { db['key2'] = 'value2' }
    }.not_to raise_error
  end

  # -----------------------------------------------------------------------
  # 8. Transaction object survives GC after finishing
  #    Verifies that a finished transaction's Ruby object can be
  #    collected without corrupting the environment
  # -----------------------------------------------------------------------
  it 'allows GC to collect finished transaction objects safely' do
    10.times do |i|
      env.transaction { db["key#{i}"] = "value#{i}" }
    end
    # force collection of all those transaction objects
    GC.compact
    GC.start
    expect {
      env.transaction { db['final'] = 'write' }
    }.not_to raise_error
  end

  # -----------------------------------------------------------------------
  # 9. Many databases, many transactions, GC between each
  #    Closer to the Store::Digest workload profile
  # -----------------------------------------------------------------------
  it 'handles multiple named databases with GC.compact between writes' do
    dbs = %w[alpha beta gamma delta].map do |name|
      env.database(name, create: true)
    end
    GC.compact

    10.times do |i|
      env.transaction do
        dbs.each { |d| d["key#{i}"] = "value#{i}" }
      end
      GC.compact
    end

    env.transaction(true) do
      dbs.each do |d|
        10.times { |i| expect(d["key#{i}"]).to eq "value#{i}" }
      end
    end
  end
end
