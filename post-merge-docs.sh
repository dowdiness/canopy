#!/bin/bash
claude -p "Update test counts in all docs to match actual test output from 'moon test'. Update benchmark tables if bench results changed. Commit with message 'docs: update test counts and benchmarks'" --allowedTools "Bash,Read,Edit,Grep"
