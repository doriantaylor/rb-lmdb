require 'helper'
require 'lmdb'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'LMDB pseudo-transactions (RO nested inside RW)' do
  let(:path) { Dir.mktmpdir }
  let(:env)  { LMDB.new(path, mapsize: 2**20) }
  let(:db)   { env.database('test', create: true) }

  before(:each) { db } # ensure db is opened inside a txn before tests run

  after(:each) do
    env.close rescue nil
    FileUtils.rm_rf path
  end

  it 'should not have anything in the readers' do
    expect(env.info[:numreaders]).to eq(0)
    expect(env.reader_check).to eq(0)
    expect(env.reader_list.first).to eq("(no active readers)\n")
  end

  # -----------------------------------------------------------------------
  # The core bug: RO transaction nested inside RW must not abort the RW txn
  # when the RO block raises.
  # -----------------------------------------------------------------------

  it 'does not abort the outer RW transaction when the inner RO block raises' do

    # warn env.reader_list.inspect

    expect {
      env.transaction do

        db['key'] = 'value'

        # This inner RO transaction raises. Before the fix this silently
        # aborted the outer RW transaction, causing the subsequent write
        # to produce EINVAL / "Invalid argument".
        begin
          env.transaction(true) do
            # warn env.reader_list.inspect
            raise 'deliberate error inside RO block'
          end
        rescue RuntimeError
          # swallow — the outer RW transaction should survive this
        end

        # This write must succeed. If the outer txn was aborted by the
        # inner RO block's exception, this raises LMDB::Error::BadTxn or
        # produces "Invalid argument".
        db['key2'] = 'value2'
      end
    }.not_to raise_error

    # And the writes must have actually committed
    env.transaction(true) do
      expect(db['key']).to  eq 'value'
      expect(db['key2']).to eq 'value2'
    end
  end

  # -----------------------------------------------------------------------
  # commit/abort on a pseudo-txn are no-ops: the outer RW txn survives
  # -----------------------------------------------------------------------

  it 'treats txn.commit inside a pseudo-transaction as a no-op' do
    env.transaction do
      db['before'] = 'yes'

      env.transaction(true) do |pseudo|
        # explicit commit on a pseudo-txn should be a no-op, not an error,
        # and must not commit the outer RW transaction prematurely
        pseudo.commit
      end

      # outer txn still alive — this must not raise
      db['after'] = 'yes'
    end

    env.transaction(true) do
      expect(db['before']).to eq 'yes'
      expect(db['after']).to  eq 'yes'
    end
  end

  it 'treats txn.abort inside a pseudo-transaction as a no-op' do
    env.transaction do
      db['key'] = 'written'

      env.transaction(true) do |pseudo|
        # explicit abort on a pseudo-txn must not roll back the outer txn
        pseudo.abort
      end

      # outer txn still alive
      db['key2'] = 'also written'
    end

    env.transaction(true) do
      expect(db['key']).to  eq 'written'
      expect(db['key2']).to eq 'also written'
    end
  end

  # -----------------------------------------------------------------------
  # pseudo-txn correctly reflects the read view of the enclosing RW txn
  # -----------------------------------------------------------------------

  it 'can read writes made in the outer RW transaction via the pseudo-transaction' do
    env.transaction do
      db['visible'] = 'yes'

      result = env.transaction(true) do |pseudo|
        # writes made in the outer txn should be visible here since
        # we are using the same underlying MDB_txn
        db['visible']
      end

      expect(result).to eq 'yes'
    end
  end

  # -----------------------------------------------------------------------
  # break from pseudo-txn exits only the inner block; outer RW continues
  # -----------------------------------------------------------------------
  it 'break from a pseudo-transaction exits only the inner block' do
    outer_continued = false

    env.transaction do
      db['key'] = 'value'

      env.transaction(true) do
        break
      end

      outer_continued = true
      db['key2'] = 'value2'
    end

    expect(outer_continued).to be true
    env.transaction(true) do
      expect(db['key']).to  eq 'value'
      expect(db['key2']).to eq 'value2'
    end
  end

  # -----------------------------------------------------------------------
  # pseudo-txn finished? predicate
  # -----------------------------------------------------------------------

  it 'marks the pseudo-transaction as finished after the block exits' do
    pseudo_ref = nil

    env.transaction do
      env.transaction(true) do |pseudo|
        pseudo_ref = pseudo
        expect(pseudo_ref.finished?).to be false
      end
    end

    # After the pseudo block exits, txn should be terminated
    expect(pseudo_ref.finished?).to be true
  end

  # -----------------------------------------------------------------------
  # Nested pseudo-txns (RO inside RO inside RW) also work correctly
  # -----------------------------------------------------------------------

  it 'handles doubly-nested pseudo-transactions without corrupting the txn chain' do
    env.transaction do
      db['key'] = 'value'

      env.transaction(true) do
        env.transaction(true) do
          expect(db['key']).to eq 'value'
        end
        # still inside the first RO pseudo here
        expect(db['key']).to eq 'value'
      end

      # outer RW still alive
      db['key2'] = 'value2'
    end

    env.transaction(true) do
      expect(db['key']).to  eq 'value'
      expect(db['key2']).to eq 'value2'
    end
  end

  # -----------------------------------------------------------------------
  # The original store-digest scenario: exception inside a method that
  # opens its own RO transaction while called from inside a RW transaction.
  # This is the real-world pattern that was failing.
  # -----------------------------------------------------------------------

  it 'survives the mark_meta_deleted pattern: RO read inside a RW write block' do
    # Simulate the pattern from store-digest's v1.rb:
    #   mark_meta_deleted opens @lmdb.transaction (RW)
    #     then calls get_meta which opens @lmdb.transaction(true) (RO)
    #     get_meta raises
    #   mark_meta_deleted should survive and continue

    def read_with_possible_raise(env, db, should_raise)
      env.transaction(true) do
        raise 'record not found' if should_raise
        db['key']
      end
    end

    expect {
      env.transaction do
        db['key'] = 'value'

        # First inner RO call raises — simulates get_meta failing
        begin
          read_with_possible_raise(env, db, true)
        rescue RuntimeError
          # expected, swallow it
        end

        # Second inner RO call succeeds — simulates a subsequent read
        val = read_with_possible_raise(env, db, false)
        expect(val).to eq 'value'

        db['key2'] = 'also committed'
      end
    }.not_to raise_error

    env.transaction(true) do
      expect(db['key']).to  eq 'value'
      expect(db['key2']).to eq 'also committed'
    end
  end
end
