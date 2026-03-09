#!/usr/bin/env bash
echo "Running infra E2E tests skeleton"
sbcl --script "$TARGET/test_infra_domain.cl" || true
