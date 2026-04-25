#!/bin/bash
set -e

echo "=== Minimal sandbox startup overhead repro ==="
echo ""
echo "This demonstrates the ~5s sandbox startup penalty"
echo "for a trivial echo command (no Python, no network, no I/O)."
echo ""

cd "$(dirname "$0")"

# Native
echo "1. Native echo:"
time echo "hello from native"

# Minimal — warm cache (run once first to ensure images are downloaded)
echo ""
echo "2. minimal run (warm cache):"
time minimal run echo 2>&1 | grep -v "sync-helper\|minimal-entry"

echo ""
echo "=== Results ==="
echo "Native:   ~0.001s"
echo "minimal:  ~5s (sandbox/container startup, warm cache)"
echo ""
echo "Overhead: ~5,000x for a task that does nothing."
