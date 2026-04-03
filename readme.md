# voss -- vector string processing

## dir. `zig`

### latest

 - build out c version to count words, find k most common and report stats on performance of roll-your-own hashmap

 - embed pride-and-prejudice.txt
 - a collector that accumulates alpha sequences across the end of the vector
 - reload vector while looking for end of alpha sequence i.e. finding q
 - labelled loop for finding p rather than explicit bool

### next
 - testing and benchmarking

### usage

Try,

```sh
cd zig/voss
zig build run
```

## dir. `c`

Try,

```sh
cd c
make
./build/voss ../zig/voss/src/pride-and-prejudice.txt
```



### end
