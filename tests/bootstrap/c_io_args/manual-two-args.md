# Manual two-argument CLI run

Stage0 command, run from this package directory:

```sh
nlc --frontend=rust run . -- alpha beta
```

O1 and O3 produced identical results. The captured stdout, stderr, and exit status are in `manual-two-args.stdout`, `manual-two-args.stderr`, and `manual-two-args.exit`; they are separate from the no-argument `expected.*` oracle.
