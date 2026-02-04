#!/bin/bash

# Release Preparation Script
# This script checks for common issues before release

echo "🔍 Today RSS Reader - Release Check"
echo "====================================="
echo ""

# Check for debug prints (excluding DEBUG-gated ones)
echo "📝 Checking for debug print statements..."
PRINTS=$(grep -r "print(" --include="*.swift" . | grep -v "//.*print(" | grep -v "#if DEBUG" | grep -v "FIXME" | grep -v "TODO" | wc -l)
if [ "$PRINTS" -gt 0 ]; then
    echo "⚠️  Found $PRINTS ungated print() statements:"
    grep -rn "print(" --include="*.swift" . | grep -v "//.*print(" | grep -v "#if DEBUG"
else
    echo "✅ No ungated print() statements found"
fi
echo ""

# Check for force unwraps
echo "⚡ Checking for force unwraps (!)..."
FORCE_UNWRAPS=$(grep -r "!" --include="*.swift" . | grep -v "!=" | grep -v "// " | wc -l)
echo "ℹ️  Found $FORCE_UNWRAPS potential force unwraps (review manually)"
echo ""

# Check for TODOs and FIXMEs
echo "📌 Checking for TODO/FIXME comments..."
TODOS=$(grep -r "TODO\|FIXME" --include="*.swift" . | wc -l)
if [ "$TODOS" -gt 0 ]; then
    echo "⚠️  Found $TODOS TODO/FIXME comments:"
    grep -rn "TODO\|FIXME" --include="*.swift" .
else
    echo "✅ No TODO/FIXME comments found"
fi
echo ""

# Check for empty catch blocks
echo "🪲 Checking for empty catch blocks..."
EMPTY_CATCH=$(grep -r "catch.*{.*}" --include="*.swift" . | wc -l)
if [ "$EMPTY_CATCH" -gt 0 ]; then
    echo "⚠️  Found $EMPTY_CATCH empty catch blocks"
else
    echo "✅ No empty catch blocks found"
fi
echo ""

echo "====================================="
echo "✅ Release check complete!"
echo ""
echo "Next steps:"
echo "1. Review any warnings above"
echo "2. Run tests: Product → Test (⌘U)"
echo "3. Build for Release: Product → Archive"
echo "4. See RELEASE_CHECKLIST.md for full list"
