# AX dumps

What the accessibility API answers about real windows on a real machine, one file per window, recorded by `make axdump` (`Tools/AXDump`). `AXDumpFixtureTests` holds the admission gate (`WindowSnapshot.isAdmissible`) to every one of them, so a rule that starts managing the Finder desktop or dropping a browser window fails the suite instead of the day.

Recording:

```
make axdump                  # every window of every regular application
make axdump ARGS="Safari"    # only the applications whose name contains Safari
```

An existing file is kept, not overwritten: delete it to re-record. Titles are never written, only what the gate reads.

`admissible` is the recorder's guess and the whole point of the fixture, so it is the one field to review before committing: it says whether OttoWM *should* manage that window, which is a judgement about the window, not a reading of it. `note` is free text for saying which window this was — a Quick Look panel, a preferences sheet, the desktop.
