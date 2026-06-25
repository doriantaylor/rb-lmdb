module LMDB
  class Environment

    # Start a new transaction if there isn't already one going.
    #
    # @param readonly [false, true]
    # @param block [Proc] the block to run
    # @yieldparam [LMDB::Transaction] the transaction handle
    # @yieldreturn [Object] your pick
    # @return [Object] whatever the block returns
    #
    def transaction? readonly = false, &block
      raise ArgumentError, 'no block for conditional transaction' unless block

      t = active_txn
      t ? block.call(t) : transaction(!!readonly, &block)
    end
  end

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
    def each &block
      env.transaction? true do
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
      return enum_for :each_key unless block

      env.transaction? true do
        cursor do |c|
          while (rec = c.next true)
            block.call rec.first
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
      return enum_for :each_value, key unless block

      op = -> txn do
        value = get(key) or return
        unless dupsort?
          block.call value
          return
        end

        cursor do |c|
          rec = c.set key
          while rec
            block.call rec.last
            rec = c.next_range key
          end
        end
      end

      env.transaction? true, &op
    end

    # Return the cardinality (number of duplicates) of a given
    # key. Works whether +:dupsort+ is set or not.
    # @param key [#to_s] The key in question.
    # @return [Integer] The number of entries under the key.
    def cardinality(key)
      ret = 0
      env.transaction? true do
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
      env.transaction? true do
        if v = get(key)
          if value.nil? or value.to_s == v
            true
          elsif !dupsort?
            false
          else
            ret = false
            cursor { |c| ret = !!c.set(key, value) }

            ret
          end
        end
      end
    end

    # Conditionally put a value into the database.
    #
    # @param key [#to_s] The key of the record
    # @param value [#to_s, nil] the (optional) value
    # @param options [Hash] options
    #
    # @see #put
    #
    # @return [void]
    #
    def put?(key, value = nil, **options)
      # early bailout
      return if value.nil?

      flags = { (dupsort? ? :nodupdata : :nooverwrite) => true }

      env.transaction? do |txn|
        put(key, value, **options.merge(flags)) unless has?(key, value)
      end
    end

    # Delete the key (and optional value pair) if it exists; do not
    # complain about missing keys.
    #
    # @param key [#to_s] The key of the record
    # @param value [#to_s, nil] The optional value
    #
    # @see #delete
    #
    # @return [void]
    #
    def delete?(key, value = nil)
      env.transaction? { |txn| delete(key, value) if has?(key, value) }
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
  end
end
