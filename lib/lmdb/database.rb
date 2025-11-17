module LMDB
  class Database
    include Enumerable

    # Iterate through the records in a database
    # @yield [i] Gives a record [key, value] to the block
    # @yieldparam [Array] i The key, value pair for each record
    # @example
    #    db.each do |record|
    #      key, value = record
    #      puts "at #{key}: #{value}"
    #    end
    def each
      maybe_txn true do
      # env.transaction do
        cursor do |c|
          while i = c.next
            yield(i)
          end
        end
      end
    end

    # Retrieve the value of a record from a database
    # @param key the record key to retrieve
    # @return value of the record for that key, or nil if there is
    #      no record with that key
    # @see #get(key)
    def [](key)
      get(key)
    end

    # Set (write or update) a record in a database.
    # @param key key for the record
    # @param value the value of the record
    # @return returns the value of the record
    # @see #put(key, value)
    # @example
    #      db['a'] = 'b'     #=> 'b'
    #      db['b'] = 1234    #=> 1234
    #      db['a']           #=> 'b'
    def []=(key, value)
      put key, value
      value
    end

    # Get the keys as an array.
    # @return [Array] of keys.
    def keys
      each_key.to_a
    end

    # Iterate over each key in the database, skipping over duplicate records.
    #
    # @yield key [String] the next key in the database.
    # @return [Enumerator] in lieu of a block.
    def each_key(&block)
      return enum_for :each_key unless block_given?
      maybe_txn true do
      #env.transaction do
        cursor do |c|
          while (rec = c.next true)
            yield rec.first
          end
        end
      end
    end

    # Iterate over the duplicate values of a given key, using an
    # implicit cursor. Works whether +:dupsort+ is set or not.
    #
    # @param key [#to_s] The key in question.
    # @yield value [String] the next value associated with the key.
    # @return [Enumerator] in lieu of a block.
    def each_value(key, &block)
      return enum_for :each_value, key unless block_given?

      value = get(key) or return
      unless dupsort?
        yield value
        return
      end

      maybe_txn true do
      # env.transaction do
        cursor do |c|
          rec = c.set key
          while rec
            yield rec.last
            rec = c.next_range key
          end
        end
      end
    end

    # Return the cardinality (number of duplicates) of a given
    # key. Works whether +:dupsort+ is set or not.
    # @param key [#to_s] The key in question.
    # @return [Integer] The number of entries under the key.
    def cardinality(key)
      ret = 0
      maybe_txn true do
      # env.transaction do
        if get key
          if dupsort?
            cursor do |c|
              c.set key
              ret = c.count
            end
          else
            ret = 1
          end
        end
      end
      ret
    end

    # Test if the database has a given key (or, if opened in
    # +:dupsort+, value)
    def has?(key, value = nil)
      v = get(key) or return false
      return true if value.nil? or value.to_s == v
      return false unless dupsort?

      # warn "checking dupsort value `#{value.inspect}` (#{value.class})"

      ret = false
      # read-only txn was having trouble being nested inside a read-write
      maybe_txn true do
      # env.transaction true do
      # env.transaction do
        cursor { |c| ret = !!c.set(key, value) }
      end
      ret
    end

    # Conditionally put a value into the database.
    #
    # @param key [String] The key of the record
    # @param value [String] the (optional) value
    # @param options [Hash] options
    #
    # @see #put
    #
    # @return [void]
    #
    def put?(key, value = nil, **options)
      begin
        put key, value, **options
      rescue LMDB::Error::KEYEXIST
        nil
      end
    end

    # Delete the key (and optional value pair) if it exists; do not
    # complain about missing keys.
    # @param key [#to_s] The key of the record
    # @param value [#to_s] The optional value
    #
    # @see #delete
    #
    # @return [void]
    #
    def delete?(key, value = nil, **options)
      begin
        delete key, value, **options
      rescue LMDB::Error::NOTFOUND
        nil
      end
    end

    # Return how many records there are in this database.
    #
    # @return the number of records in this database
    def size
      stat[:entries]
    end

    #
    # @return whether the database is empty
    def empty?
      stat[:entries] == 0
    end

    private

    # having trouble with read-only transactions embedded in
    # read-write for some reason; can't pin it down to test it yet so
    # going to do this (djt; 2020-02-10)
    #
    # 2025-11-14: this miiiigght no longer be necessary?? like as of
    # whenever i implemented that short-circuiting code
    #
    def maybe_txn(readonly, &block)
      if t = env.active_txn
        # warn "reusing #{t.readonly? ? 'read-only ' : ''}txn #{t.inspect}"
        yield t
      else
        env.transaction !!readonly do |t|
          # warn "new #{t.readonly? ? 'read-only ' : ''}txn #{t.inspect}"
          yield t
        end
      end
    end
  end
end
