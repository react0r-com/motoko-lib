# motoko-lib
Motoko general purpose libraries

## vector

Vector with O(sqrt(n)) memory waste based on paper "Resizable Arrays in Optimal Time and Space" by Brodnik, Carlsson, Demaine, Munro and Sedgewick (1999).

## sha2

A new implementation of the whole SHA2 family that is also cycle optimized. 
We benchmarked the incremental cost per block/chunk to be the following:

sha224/sha256: 27,596 cycles per chunk (64 bytes) or 431 cycles per byte
sha512 variants: 40,128 cycles per chunk (128 bytes) or 313 cycles per byte

sha256 of the empty blob takes 66,659 cycles. This means the per message overhead (setting up the Digest class, padding, length bytes, and extraction of the digest) is 39,063 cycles or equivalent ot the incremental cost of 1.41 chunks.

sha512 of the empty blob takes 110,881 cycles. This means the per message overhead (setting up the Digest class, padding, length bytes, and extraction of the digest) is 70,753 cycles or equivalent to the incremental cost of 1.76 chunks.

### Comparison

We measured other implementations that are being used right now to have an incremental cost per block/chunk of 48,818-49,717 cycles for sha224/sha256. Our cost is ~55% of that.

We measured other implementations that are being used right now to have a cost of 94,384-98,924 cycles for sha256 of the empty blob. Our implementation is ~70% of that.