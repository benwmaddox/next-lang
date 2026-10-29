# Filesystem smoke fixture

This fixture takes its root directory as an `Arg`. The minimal compiler accepts `Arg` for `Fs.join` and `Fs.list_with_extension`; it does not accept the literal `.` as a directory path. Run it from the package directory with one argument:

```sh
nlc --frontend=rust run . -- .
```

`expected.args` records that argument. The program reads `input.data`, writes and rereads `output.data`, then checks the four `.data` entries in byte-sorted order.
