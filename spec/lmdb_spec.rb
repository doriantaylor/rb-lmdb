# coding: binary
require 'helper'

describe LMDB do
  let(:env) { LMDB.new(path, mapsize: 2**20) }
  after     { env.close rescue nil }

  let(:db)  { env.database }

  it 'has version constants' do
    expect(LMDB::LIB_VERSION_MAJOR).to be_instance_of(Integer)
    expect(LMDB::LIB_VERSION_MINOR).to be_instance_of(Integer)
    expect(LMDB::LIB_VERSION_PATCH).to be_instance_of(Integer)
    expect(LMDB::LIB_VERSION).to be_instance_of(String)
    expect(LMDB::VERSION).to be_instance_of(String)
  end

  describe LMDB::Environment do
    subject { env }

    it 'should return flags' do
      expect(subject.flags).to be_instance_of(Array)
    end

    describe 'new' do
      it 'returns environment' do
        env = LMDB::Environment.new(path)
        expect(env).to be_instance_of(described_class)
        env.close
      end

      it 'accepts block' do
        out = LMDB::Environment.new(path) do |env|
          expect(env).to be_instance_of(described_class)
          42
        end
        expect(out).to eq(42)
      end

      it 'accepts options' do
        env = LMDB::Environment.new(path, nosync: true, mode: 0777,
          maxreaders: 777, mapsize: 111111, maxdbs: 666)
        expect(env).to be_instance_of(described_class)
        expect(env.info[:maxreaders]).to eq(777)
        expect(env.info[:mapsize]).to eq(111111)
        expect(env.flags.include? :nosync).to be_truthy
        env.close

        env = LMDB::Environment.new(path, nosync: false)
        expect(env.flags.include? :nosync).to be_falsy
        env.close
      end
    end

    it 'should return stat' do
      stat = env.stat
      expect(stat[:psize]).to be_instance_of(Integer)
      expect(stat[:depth]).to be_instance_of(Integer)
      expect(stat[:branch_pages]).to be_instance_of(Integer)
      expect(stat[:leaf_pages]).to be_instance_of(Integer)
      expect(stat[:overflow_pages]).to be_instance_of(Integer)
      expect(stat[:entries]).to be_instance_of(Integer)
    end

    it 'should return info' do
      info = env.info
      expect(info[:mapaddr]).to be_instance_of(Integer)
      expect(info[:mapsize]).to be_instance_of(Integer)
      expect(info[:last_pgno]).to be_instance_of(Integer)
      expect(info[:last_txnid]).to be_instance_of(Integer)
      expect(info[:maxreaders]).to be_instance_of(Integer)
      expect(info[:numreaders]).to be_instance_of(Integer)
    end

    it 'should set mapsize' do
      size_before = env.info[:mapsize]
      env.mapsize = size_before * 2
      expect(env.info[:mapsize]).to eq(size_before * 2)
    end

    it 'should copy' do
      target = mkpath('copy')
      expect(subject.copy(target)).to be_nil
    end

    it 'should sync' do
      expect(subject.sync).to be_nil
    end

    it 'should force-sync' do
      expect(subject.sync(true)).to be_nil
    end

    it 'should accept custom flags' do
      expect(subject.flags.include? :nosync).to be_falsy

      subject.set_flags :nosync
      expect(subject.flags.include? :nosync).to be_truthy

      subject.clear_flags :nosync
      expect(subject.flags.include? :nosync).to be_falsy
    end

    describe 'databases' do
      it 'returns empty list when there are no named databases' do
        expect(subject.databases).to eq([])
      end

      it 'returns list of named databases' do
        db1 = subject.database 'db1', create: true
        db2 = subject.database 'db2', create: true
        expect(subject.databases).to eq(['db1', 'db2'])
      end

      it 'returns list of named databases when there are non-database kes in the main db' do
        main = subject.database
        main['key'] = 'value'
        subject.database 'db1', create: true
        subject.database 'db2', create: true

        expect(subject.databases).to eq(['db1', 'db2'])
      end
    end

    describe LMDB::Transaction do
      subject { env }

      it 'should create transactions' do
        expect(subject.active_txn).to be_nil
        subject.transaction do |txn|
          expect(subject.active_txn).to eq(txn)
          expect(txn).to be_instance_of(described_class)
          txn.abort
          expect(subject.active_txn).to be_nil
        end
        expect(subject.active_txn).to be_nil
      end

      it 'should create read-only transactions' do
        expect(subject.active_txn).to be_nil
        subject.transaction(true) do |txn|
          expect(subject.active_txn).to eq(txn)
          expect(txn).to be_instance_of(described_class)
          txn.abort
          expect(subject.active_txn).to be_nil
        end
        expect(subject.active_txn).to be_nil
      end

      it 'can create child transactions' do
        expect(subject.active_txn).to be_nil
        env.transaction do |txn|
          expect(subject.active_txn).to eq(txn)
          env.transaction do |ctxn|
            expect(subject.active_txn).to eq(ctxn)
            ctxn.abort
            expect(subject.active_txn).to eq(txn)
          end
          expect(subject.active_txn).to eq(txn)
        end
        expect(subject.active_txn).to be_nil
      end

      it 'should support aborting parent transaction' do
        expect(subject.active_txn).to be_nil
        env.transaction do |txn|
          expect(subject.active_txn).to eq(txn)
          env.transaction do |ctxn|
            expect(subject.active_txn).to eq(ctxn)
            db['key'] = 'value'
            txn.abort
            expect(subject.active_txn).to be_nil
          end
          expect(subject.active_txn).to be_nil
        end
        expect(db['key']).to be_nil
        expect(subject.active_txn).to be_nil
      end

      it 'should support comitting parent transaction' do
        expect(subject.active_txn).to be_nil
        env.transaction do |txn|
          expect(subject.active_txn).to eq(txn)
          env.transaction do |ctxn|
            expect(subject.active_txn).to eq(ctxn)
            db['key'] = 'value'
            txn.commit
            expect(subject.active_txn).to be_nil
          end
          expect(subject.active_txn).to be_nil
        end
        expect(db['key']).to eq('value')
        expect(subject.active_txn).to be_nil
      end

      it 'should get environment' do
        env2 = nil
        env.transaction do |txn|
          env2 = txn.env
        end
        expect(env2).to eq(env)
      end
    end
  end

  describe LMDB::Database do
    subject { db }

    it 'should return flags' do
      expect(subject.flags).to be_instance_of(Hash)
      expect(subject.dupsort?).to be_falsy
      expect(subject.dupfixed?).to be_falsy
    end

    it 'should support named databases' do
      main = env.database
      # funnily it complains in 2.7 unless i do this
      dbopts = { create: true }
      db1 = env.database 'db1', create: true # actually no it doesn't wtf
      db2 = env.database 'db2', **dbopts

      # this should not crash
      expect(env[:db1].size).to eq(0)

      main['key'] = '1'
      db1['key'] = '2'
      db2['key'] = '3'

      expect(main['key']).to eq(?1)
      expect(db1['key']).to  eq(?2)
      expect(db2['key']).to  eq(?3)
    end

    it 'should get/put data' do
      expect(subject.get 'cat').to be_nil
      expect(subject.put 'cat', 'garfield').to be_nil
      expect(subject.get 'cat').to eq('garfield')

      # check for key-value pairs on non-dupsort database
      expect(subject.has? 'cat', 'garfield').to be_truthy
      expect(subject.has? 'cat', 'heathcliff').to be_falsy

      subject.put?('dog', 'odie')
      expect(subject.has? 'dog', 'odie').to be_truthy
    end

    it 'should delete by key' do
      expect { subject.delete('cat') }.to raise_error(LMDB::Error::NOTFOUND)
      expect {
        subject.delete 'cat', 'garfield'
      }.to raise_error(LMDB::Error::NOTFOUND)

      subject.put('cat', 'garfield')
      expect(subject.delete 'cat').to be_nil
      expect { subject.delete 'cat' }.to raise_error(LMDB::Error::NOTFOUND)

      subject.put('cat', 'garfield')
      expect(subject.delete 'cat', 'garfield').to be_nil
      expect {
        subject.delete 'cat', 'garfield' }.to raise_error(LMDB::Error::NOTFOUND)

      # soft delete
      expect(subject.delete? 'cat', 'heathcliff').to be_nil
    end

    it 'stores key/values in same transaction' do
      expect(db.put 'key', 'value').to be_nil
      expect(db.get 'key').to eq('value')
    end

    it 'stores key/values in different transactions' do
      env.transaction do
        expect(db.put 'key', 'value').to be_nil
        expect(db.put 'key2', 'value2').to be_nil
        env.transaction do
          expect(db.put 'key3', 'value3').to be_nil
        end
      end

      env.transaction do
        expect(db.get 'key').to eq('value')
        expect(db.get 'key2').to eq('value2')
        env.transaction do
          expect(db.get 'key3').to eq('value3')
        end
      end
    end

    it 'should not complain when you break out of a transaction' do
      env.transaction do |txn|
        db.put 'key4', 'value4'
        break
      end

      expect(db.get 'key4').to eq('value4')
    end

    it 'should return stat' do
      expect(db.stat).to be_instance_of(Hash)
    end

    it 'should return size' do
      expect(db.size).to eq(0)
      db.put('key', 'value')
      expect(db.size).to eq(1)
      db.put('key2', 'value2')
      expect(db.size).to eq(2)
    end

    it 'should be enumerable' do
      db['k1'] = 'v1'
      db['k2'] = 'v2'
      expect(db.to_a).to eq([['k1', 'v1'], ['k2', 'v2']])
    end

    it 'should have shortcuts' do
      db['key'] = 'value'
      expect(db['key']).to eq('value')
    end

    it 'should store binary' do
      bin1 = "\xAAx\BB\xCC1"
      bin2 = "\xAAx\BB\xCC2"
      db[bin1] = bin2
      db['key'] = bin2
      expect(db[bin1]).to eq(bin2)
      expect(db['key']).to eq(bin2)
    end

    it 'should get environment' do
      main = env.database
      db1 = env.database('db1', create: true)
      expect(main.env).to eq(env)
      expect(db1.env).to eq(env)
    end

    it 'should iterate over/list keys' do
      db['k1'] = 'v1'
      db['k2'] = 'v2'
      expect(db.keys.sort).to eq(%w[k1 k2])
    end
  end

  describe LMDB::Cursor do
    before do
      db.put('key1', 'value1')
      db.put('key2', 'value2')
    end

    it 'should get first key/value' do
      db.cursor do |c|
        expect(c.first).to eq(['key1', 'value1'])
      end
    end

    it 'should get last key/value' do
      db.cursor do |c|
        expect(c.last).to eq(['key2', 'value2'])
      end
    end

    it 'should get next key/value' do
      db.cursor do |c|
        c.first
        expect(c.next).to eq(['key2', 'value2'])
      end
    end

    it 'should seek to key' do
      db.cursor do |c|
        expect(c.set 'key1').to eq(['key1', 'value1'])
      end
    end

    it 'should seek to closest key' do
      db.cursor do |c|
        expect(c.set_range 'key0').to eq(['key1', 'value1'])
      end
    end

    it 'should seek to key with nuls' do
      db.cursor do |c|
        expect(c.set_range '\x00').to eq(['key1', 'value1'])
      end
    end

    it 'should seek within range' do
      db.cursor do |c|
        db.put('key0', 'value0')
        c.first
        expect(c.next_range 'key1').to eq(['key1', 'value1'])
        expect(c.next_range 'key1').to be_nil
      end
    end

    it 'should set to a key-value pair when db is dupsort' do
      dupdb = env.database 'dupsort', create: true, dupsort: true

      # check flag while we're at it
      expect(dupdb.flags[:dupsort]).to be_truthy
      expect(dupdb.dupsort?).to be_truthy
      expect(dupdb.dupfixed?).to be_falsy

      # add the no-op keyword to trigger a complaint from ruby 2.7
      dupdb.put 'key1', 'value1', nodupdata: false
      dupdb.put 'key1', 'value2'
      dupdb.put 'key2', 'value3'
      dupdb.cursor do |c|
        expect(c.set 'key1', 'value2').to eq(['key1', 'value2'])
        expect(c.set 'key1', 'value1').to eq(['key1', 'value1'])
        expect(c.set 'key1', 'value3').to be_nil
      end

      # this should do nothing
      expect(dupdb.put? 'key1', 'value1', nodupdata: true).to be_nil

      # this is basically an extended test of `cursor.set key, val`
      expect(dupdb.has? 'key1', 'value1').to be_truthy
      expect(dupdb.has? 'key1', 'value2').to be_truthy
      expect(dupdb.has? 'key1', 'value0').to be_falsy

      # match the contents of key1
      expect(dupdb.each_value('key1').to_a.sort).to eq(['value1', 'value2'])

      # we should have two entries for key1
      expect(dupdb.cardinality 'key1').to eq(2)

      expect(dupdb.each_key.to_a.sort).to eq(['key1', 'key2'])

      # XXX move this or whatever
      env.transaction do |t|
        dupdb.put 'key1', 'value1' unless dupdb.has? 'key1', 'value1'
      end
    end

    it 'should complain setting a key-value pair without dupsort' do
      db.cursor do |c|
        expect { c.set('key1', 'value1') }.to raise_error(LMDB::Error)
      end
    end

    it 'should raise without block or txn' do
      expect { db.cursor.next }.to raise_error(LMDB::Error)
    end

    it 'should raise outside txn' do
      c = nil
      env.transaction { c = db.cursor }
      expect { c.next }.to raise_error(LMDB::Error)
    end

    it 'should get database' do
      db2 = nil
      env.transaction { c = db.cursor; db2 = c.database }
      expect(db2).to eq(db)
    end

    it 'should nest a read-only txn in a read-write' do
      env.transaction do |t|
        # has? opens a read-only transaction
        db.put 'hurr', 'durr' unless db.has? 'hurr', 'durr'
      end
    end

    it 'should croak when cursor key is not given a string' do
      expect do
        db.cursor do |c|
          c.set 1
        end
      end.to raise_error(ArgumentError)
    end

    it 'should croak when cursor value is not given a string' do
      expect do
        db.cursor do |c|
          c.set 'hi', 1
        end
      end.to raise_error(ArgumentError)
    end
  end
end
