#!/usr/bin/env python3
"""Run Stage 2 scaling cells in isolated processes.

Cold repetitions are separate process launches. Warm samples for a cell share
one process, and report keys retain the process id so samples are never pooled.
"""
import argparse
import os
import subprocess
import sys

p = argparse.ArgumentParser()
p.add_argument("--corpus", default="ordinary,structure")
p.add_argument("--targets", default="1000,10000,50000,100000,250000,500000,1270000")
p.add_argument("--phases", default="parse,ir,extract")
p.add_argument("--cold-reps", type=int, default=3)
p.add_argument("--warmups", type=int, default=20)
p.add_argument("--samples", type=int, default=20)
p.add_argument("--output", type=argparse.FileType("w"), default=sys.stdout)
p.add_argument("--timeout", type=int, default=600)
a = p.parse_args()

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cwd = os.path.join(root, "apps", "loomark")
base = os.environ.copy()
base.update({
    "LOOMARK_STAGE2_SCALING": "1",
    "LOOMARK_STAGE2_SCALING_CORPUS": "",
    "LOOMARK_STAGE2_SCALING_TARGET": "",
    "LOOMARK_STAGE2_SCALING_PHASE": "",
})

def launch(corpus, target, phase, run, warmups, samples):
    env = base | {
        "LOOMARK_STAGE2_SCALING_CORPUS": corpus,
        "LOOMARK_STAGE2_SCALING_TARGET": str(target),
        "LOOMARK_STAGE2_SCALING_PHASE": phase,
        "LOOMARK_STAGE2_SCALING_RUN": run,
        "LOOMARK_STAGE2_SCALING_WARMUPS": str(warmups),
        "LOOMARK_STAGE2_SCALING_SAMPLE_COUNT": str(samples),
    }
    cmd = ["moon", "test", "internal/document_lead", "--target", "js", "--release",
           "--filter", "stage2 size scaling raw samples"]
    result = subprocess.run(cmd, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=a.timeout)
    a.output.write(f"PROCESS run={run} corpus={corpus} target={target} phase={phase} exit={result.returncode}\n")
    a.output.write(result.stdout)
    a.output.flush()
    if result.returncode:
        raise SystemExit(result.returncode)

for corpus in a.corpus.split(","):
    for target in a.targets.split(","):
        for phase in a.phases.split(","):
            for rep in range(a.cold_reps):
                launch(corpus, target, phase, f"cold-{rep}", 0, 1)
            launch(corpus, target, phase, "warm", a.warmups, a.samples)
