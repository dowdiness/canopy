# Canonical Gate R0 run-bundle ownership. The output directory is runner-owned:
# every run starts empty, and every classified failure replaces its contents
# with exactly the ten registered files before returning control.

export def artifact-paths [] {
  [
    "manifest.json"
    "result.json"
    "capability-ledger.json"
    "candidate-captures.jsonl"
    "candidate-results.json"
    "operation-matrix.jsonl"
    "oracle-differential.jsonl"
    "cold-history.jsonl"
    "negative-results.json"
    "validation.log"
  ]
}

def fail [message: string] { error make { msg: $message } }

def write-json [path: string value: any] {
  $value | to json -r | save -f $path
}

def write-jsonl [path: string rows: list<any>] {
  ($rows | each {|row| $row | to json -r } | str join "\n") + "\n" | save -f $path
}

export def reset-artifact-output [output: string] {
  if ($output | path type) == "symlink" {
    fail $"artifact output directory must not be a symlink: ($output)"
  }
  if ($output | path exists) {
    let output_type = ($output | path type)
    if $output_type != "dir" {
      fail $"artifact output path must be a directory: ($output)"
    }
  } else {
    mkdir $output
  }
  for entry in (ls -a $output) {
    rm -rf $entry.name
  }
}

export def assert-artifact-set [output: string] {
  let expected = (artifact-paths | sort)
  let actual = (ls -a $output | get name | each {|path| $path | path basename } | sort)
  if $actual != $expected {
    fail $"artifact set differs: expected=($expected | to json -r) actual=($actual | to json -r)"
  }
}

export def write-failure-bundle [output: string failure: string candidate_outcomes: list<any>] {
  reset-artifact-output $output
  write-json ($output | path join "manifest.json") {
    schema_version: 1
    run_id: "gate-r0-v1"
    status: "fail"
  }
  write-json ($output | path join "capability-ledger.json") { schema_version: 1 rows: [] }
  write-jsonl ($output | path join "candidate-captures.jsonl") []
  write-json ($output | path join "candidate-results.json") { schema_version: 1 candidates: [] }
  write-jsonl ($output | path join "operation-matrix.jsonl") []
  write-jsonl ($output | path join "oracle-differential.jsonl") []
  write-jsonl ($output | path join "cold-history.jsonl") []
  write-json ($output | path join "negative-results.json") { schema_version: 1 negatives: [] }
  $"Gate R0 failure: ($failure)\n" | save -f ($output | path join "validation.log")
  write-json ($output | path join "result.json") {
    schema_version: 1
    status: "fail"
    failure_class: $failure
    candidate_outcomes: $candidate_outcomes
    artifact_paths: (artifact-paths)
  }
  assert-artifact-set $output
}
