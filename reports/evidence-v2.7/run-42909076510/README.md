# Run 42909076510 evidence — REPRO closed for this builder

Dispatched with `double_build=true`. Both builds of head `507b25a` are byte-identical:

```
== build A
bytes=930086912
sha256=43488236624bd91725dc2c569c378fb2504de3a376630d3268c4aa34fe39939f

== build B
bytes=930086912
sha256=43488236624bd91725dc2c569c378fb2504de3a376630d3268c4aa34fe39939f

VERDICT: REPRO=IDENTICAL
```

`diff_raw_lines=0`, `differing_entries=0`, listing 25,597 lines with 0 differing rows,
7/7 sampled files identical, ISO bytes identical so `cmp` printed `identical`.

The rest of the run is green and this is the new delivery run: payload 54/54, repair 28/28,
fault injection 39, PAWDATA 12, network 17, finalize 36, TTY 56, QEMU CJK 5 cases / 96
assertions.

Scope of the claim, stated so nobody over-reads it: two consecutive builds inside one job on
one `ubuntu-24.04` runner image. Nothing here claims that a build on a different image
version, or next month, produces the same bytes.

The delivery ISO was re-downloaded from artifact `13808328141` (1,007,613,856 bytes),
extracted, and hashed locally to `4348823662…39939f`, matching the uploaded sidecar.
