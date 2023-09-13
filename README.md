# zig-lmdb

Zig bindings for LMDB.

## Benchmarks

Run the benchmarks with

```
$ zig build bench
```

### DB size: 1,000 entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |  ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | -------: |
| get random 1 entry       |        100 |   0.0008 |   0.0068 |   0.0010 | 0.0006 |  1047614 |
| get random 100 entries   |        100 |   0.0139 |   0.0163 |   0.0153 | 0.0005 |  6553960 |
| iterate over all entries |        100 |   0.0128 |   0.0135 |   0.0129 | 0.0001 | 77632157 |
| set random 1 entry       |        100 |   0.0757 |   0.1720 |   0.0884 | 0.0141 |    11315 |
| set random 100 entries   |        100 |   0.1003 |   0.2672 |   0.1330 | 0.0283 |   752023 |
| set random 1000 entries  |         10 |   0.4015 |   0.4342 |   0.4192 | 0.0085 |  2385780 |
| set random 50000 entries |         10 |  15.8318 |  16.7525 |  16.0100 | 0.2746 |  3123047 |

### DB size: 50,000 entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |   ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | --------: |
| get random 1 entry       |        100 |   0.0008 |   0.0114 |   0.0017 | 0.0011 |    590692 |
| get random 100 entries   |        100 |   0.0236 |   0.0586 |   0.0285 | 0.0056 |   3503495 |
| iterate over all entries |        100 |   0.4822 |   0.5365 |   0.4939 | 0.0131 | 101232590 |
| set random 1 entry       |        100 |   0.0555 |   0.2061 |   0.0776 | 0.0244 |     12883 |
| set random 100 entries   |        100 |   0.3706 |   0.6468 |   0.4770 | 0.0525 |    209642 |
| set random 1000 entries  |         10 |   0.9273 |   1.0940 |   0.9796 | 0.0478 |   1020816 |
| set random 50000 entries |         10 |  22.7790 |  24.2605 |  23.2632 | 0.4404 |   2149321 |

### DB size: 1,000,000 entries

|                          | iterations | min (ms) | max (ms) | avg (ms) |    std |   ops / s |
| :----------------------- | ---------: | -------: | -------: | -------: | -----: | --------: |
| get random 1 entry       |        100 |   0.0011 |   0.0159 |   0.0024 | 0.0015 |    421276 |
| get random 100 entries   |        100 |   0.0563 |   0.1477 |   0.0711 | 0.0179 |   1406206 |
| iterate over all entries |        100 |   9.7967 |  10.4872 |   9.8927 | 0.1146 | 101084570 |
| set random 1 entry       |        100 |   0.0646 |   1.3126 |   0.0977 | 0.1245 |     10233 |
| set random 100 entries   |        100 |   0.6087 |   6.3799 |   2.4047 | 0.4908 |     41586 |
| set random 1000 entries  |         10 |   8.2941 |  14.4097 |  13.1246 | 1.9790 |     76193 |
| set random 50000 entries |         10 |  51.5092 |  67.1203 |  55.4802 | 4.4941 |    901223 |
