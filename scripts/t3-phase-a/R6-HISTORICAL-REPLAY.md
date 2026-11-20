# Historical initialization replay

Current-candidate initialization regressions use the reviewed current admission source and the restart probe supplied alongside the tests. They do not require an older source file.

Historical RED replay is a separate, optional exercise. Supply the historical admission source explicitly, preserve it unchanged, and independently verify its provenance before describing it as original. A locally retained candidate copy has SHA-256 `e1be45f2eac5ea349f89d518b7206165e67dba6014237052a530c26c2f2d1768`; this hash identifies those retained bytes, not independent proof of their historical origin. The ordinary regression suite must not silently consume a private local copy.

For an authorized replay, place the independently obtained source and reviewed test dependencies in an isolated disposable directory and pass its explicit path to the historical replay harness. Record the source hash, provenance, commands, output and exit codes. Do not interpret an inaccessible or reconstructed source as authenticated historical evidence.
