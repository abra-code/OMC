#!/bin/bash
if [ -n "$ITEST_WORK" ]; then printf 'will.terminate\n' >> "$ITEST_WORK/lifetime.txt"; fi
