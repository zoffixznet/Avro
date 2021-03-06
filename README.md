# perl6 Avro support

[![Build Status](https://travis-ci.org/sylvarant/Avro.svg?branch=master)](https://travis-ci.org/sylvarant/Avro) [![artistic](https://img.shields.io/badge/license-Artistic%202.0-blue.svg?style=flat)](https://opensource.org/licenses/Artistic-2.0)

Provides a native perl6 implementation of the [Avro specification](https://avro.apache.org/docs/current/spec.html).

## TODO

This is a work in progress.
Still to implement:
- [ ] : Reader schemas and resolution
- [ ] : JSON output (OPTIONAL)

## Example

The official [python example ](https://avro.apache.org/docs/current/gettingstartedpython.html) can be rewritten in perl6 as follows.

```Perl6
use Avro; 

my $path = "testfile";
my $avro_ex = Q<<{ "namespace": "example.avro",
 "type": "record",
 "name": "User",
 "fields": [
     {"name": "name", "type": "string"},
     {"name": "favorite_number",  "type": ["int", "null"]},
     {"name": "favorite_color", "type": ["string", "null"]}]}>>;

my $schema = parse-schema($avro_ex);
my $writer =  Avro::DataFileWriter.new(:handle($path.IO.open(:w)),:schema($schema));
$writer.append({"name" => "Alyssa","favorite_number" => 256,});  
$writer.append({"name" => "Ben", "favorite_number" => 7, "favorite_color" => "red"});
$writer.close();

my $reader = Avro::DataFileReader.new(:handle($path.IO.open(:r))); 
repeat {
 say $reader.read();
} until $reader.eof;
$reader.close()
```

## License

[Artistic License 2.0](http://www.perlfoundation.org/artistic_license_2_0)




