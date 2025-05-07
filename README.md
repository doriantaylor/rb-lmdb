# LMDB

Ruby bindings for the amazing [OpenLDAP's Lightning Memory-Mapped Database (LMDB)](https://www.symas.com/lmdb/).

## Installation

Install via rubygems:

```ruby
gem install lmdb
```

## Links

* Source: <http://github.com/doriantaylor/rb-lmdb>
* Bugs:   <http://github.com/doriantaylor/rb-lmdb/issues>
* API documentation: <http://rubydoc.info/gems/lmdb/>

## API

```ruby
require 'lmdb'

env = LMDB.new(path)

maindb = env.database
subdb = env.database('subdb', create: true)

maindb['key'] = 'value'

env.transaction do
  maindb['key'] = 'value'
  subdb['key'] = 'value'
end

env.close
```

## Moneta

If you want to have a simpler interface to LMDB databases please
consider using [Moneta](https://github.com/minad/moneta). The Moneta
gem provides an LMDB adapter which uses this gem.

## License (MIT)

```
Copyright ©2013 Daniel Mendler (later changes ©2025 Dorian Taylor)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
