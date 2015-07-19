use v6;
use JSON::Tiny;

package Avro {

  #======================================
  # Exceptions
  #======================================

  class AvroException is Exception {
    method message { "Something went wrong" }
  }


  #======================================
  # improved .Str
  #  -- resolves silly warnings
  #======================================
  
  proto to_str(Mu --> Str) is export { * }
   
  multi sub to_str(Associative:D $hash)  {
    ($hash.kv.map: -> $k,$v { to_str($k) ~ " => " ~ to_str($v) }).join(",");
  }

  multi sub to_str(Positional:D $arr) {
    "[" ~ ($arr.list.map: -> $v {to_str($v)}).join(",") ~ "]"
  }

  multi sub to_str(Mu $data) {
    ($data.gist() ~~ Any.gist() ?? "Any" !! $data.Str)
  }

  #======================================
  # Low-level representations
  #======================================

  sub to_zigzag(int $n) is export {
    ($n < 0) ?? ((($n +< 1) +^ (-1)) +| 1) !! ($n +< 1)
  }

  sub from_zigzag(int $n) is export {
    ($n +& 1) ?? (-(1 + ($n +> 1))) !! ($n +> 1)
  }

  sub to_varint(int $n --> Positional:D) is export {
    my $iter = $n;
    my @result = ();
    while ( ($iter +> 7) > 0) {
      my int $byte = ($iter +& 127) +| 128;
      push(@result,$byte);
      $iter = $iter +> 7;
    }
    push(@result,$iter);
    return @result;
  }

  sub from_varint(Positional $arr --> int) is export {
    my $r = 0;
    my $position = 0;
    for $arr.values -> $byte {
      $r = $r +| (($byte +& 127) +< $position);
      $position += 7; 
    }
    return $r;
  }

  sub int_to_bytes(int $n, int $count --> Positional:D) is export {
    my $iter = $n;
    my @bytes = ();
    for 1..$count -> $i {
      my int $byte = $iter +& 0xff; 
      push(@bytes,$byte);
      $iter = $iter +> 8;  
    }
    return @bytes;
  }

  sub int_from_bytes(Positional:D $arr --> int) is export {
    my $position = 0;
    my int $result = 0;
    for $arr.values -> $byte {
      $result = $result +| ($byte +< $position);
      $position += 8;
    }
    return $result;
  }


  #======================================
  # Floating point stuff - perl6 lacking
  #======================================

  sub frexp(Rat $rat --> Positional:D) is export {

    return (0,0) if $rat == 0; 
    return ((-1),NaN) if $rat == NaN;
    return (-1,$rat) if $rat == -Inf or $rat == Inf;

    my Int $exp = 0;
    my Rat $mantissa = $rat;
    my $sign = $mantissa.sign();

    if ($mantissa.sign() == -1) {
      $mantissa = -$mantissa; 
    }

    while ($mantissa < 0.5) {
      $mantissa *= 2.0;
      $exp -= 1;
    }

    while ($mantissa >= 1.0) {
      $mantissa *= 0.5;
      $exp++;
    }

    $mantissa = $mantissa * $sign;
    return ($exp,$mantissa);
  }

  sub to_ieee(Int $nan, Int $inf, Int $ninf, Int $fsize, Int $expsize, 
    Rat $rat --> Int) {

    given $rat {
  
      when NaN { $nan }

      when Inf { $inf }

      when -Inf { $ninf }

      when 0 { 0 }

      default { 

        my FatRat $neutr = $rat.sign() == -1 ?? -$rat.FatRat !! $rat.FatRat;
        my Int $nat = $neutr.truncate;

        # compute posible positive exp
        my $plus = 0;
        my $iter = $nat;
        until $iter <= 1  {
          $plus += 1;
          $iter = $iter +> 1;
        }

        # compute fraction bits
        my FatRat $comma = $neutr - ($neutr.truncate).FatRat;
        my Int $fraction = 0;
        my $mask = 1;
        my $bytes = 0;
        my $neg = 0;
        until $comma == 0.0 or ($fsize - $plus - $bytes) == 0  {
          $bytes++;
          $comma *= 2.0;
          if $comma.truncate > 0 {
           $neg = $bytes if $neg == 0; 
           $fraction = $fraction +| $mask;
          }
          $comma = $comma - ($comma.truncate).FatRat;
          $mask = $mask +< 1;
        }
        my Int $final = 0;
        loop (my $i = 0; $i < $bytes; $i++) {
          $final = $final +| ( 1 +< ($bytes - ($i +1))) if $fraction +& 0x1;
          $fraction = $fraction +> 1;
        }
        my int $f = 0; 
        my $exp = $plus > 0 ?? $plus !! -$neg;
        $f = $f +| $final;
        $f = $f +| ( $nat +< $bytes);
        $f = ($f +< ($fsize - $bytes - $exp)) +& ((1 +< $fsize) - 1); 
        $exp = ($exp + ((2**($expsize-1)) -1)) +< $fsize;
        my Int $result = 0; 
        $result = $result +| (1 +< ($fsize + $expsize)) if $rat.sign() == -1;
        $result = $result +| $exp;
        $result = $result +| $f;
        return $result;
      }

    }

  }

#  my $float_convert = &to_ieee.assuming(nan => 0x7fc00000, inf => 0x7f800000, ninf => 0xff800000, 
#    fsize => 23, expsize => 8);

#  my $double_convert = &to_ieee.assuming(nan => 0x7ff8000000000000, inf => 0x7ff0000000000000, 
#    ninf => 0xfff0000000000000, fsize => 52, expsize => 11);

  
  # Java : floatToIntBits !temporary
  sub to_floatbits(Rat $rat --> Int) is export {
    to_ieee(0x7fc00000,0x7f800000,0xff800000,23,8,$rat);
  }

  # Java : doubleToIntBits !temporary
  sub to_doublebits(Rat $rat --> Int) is export {
    to_ieee(0x7ff8000000000000,0x7ff0000000000000,0xfff0000000000000,52,11,$rat);
  }

  # read in bytes
  sub from_floatbits(Int $n --> Rat:D) is export {

    given $n  {

      when 0x7fc00000 { NaN }

      when 0x7f800000 { Inf }

      when 0xff800000 { -Inf }

      when 0 { 0 }

      default { 
        my $sign = 1; 
        $sign = -1 if $n +& 0x80000000;
        my Int $exp = (($n +> 23) +& 0xff); 
        $exp -= 127;
        my Int $fract =  ($n +& 0x007fffff);
        my Rat $rat = 1.Rat;
        my $iter = $fract;
        for (0..22) -> $i {
         $rat += (2**($i - 23)) if $iter +& 0x1;
         $iter = $iter +> 1;
        }
        $rat = $sign.Rat * $rat * (2**$exp).Rat; 
      }
    }
  }

  sub from_doublebits(Int $n --> Rat:D) is export {

    given $n  {

      when 0x7ff8000000000000 { NaN }

      when 0x7ff0000000000000  { Inf }

      when 0xfff0000000000000 { -Inf }

      when 0 { 0 }

      default {
        my $sign = 1;
        $sign = -1 if $n +& 0x8000000000000000;
        my Int $exp = (($n +> 52) +& 0x7ff); 
        $exp -= 1023;
        my Int $fract = ($n +& 0x000fffffffffffff);
        my FatRat $rat = 1.FatRat;
        my $iter = $fract;
        for (0..51) -> $i {
         $rat += (2**($i - 52)) if $iter +& 0x1;
         $iter = $iter +> 1;
        }
        $rat = $sign.FatRat * $rat * (2**$exp).FatRat; 
        $rat.Rat;
      }
    }
  }

}
