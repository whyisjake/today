---
applyTo: "Today/Utilities/Texturizer.swift"
---

# Texturizer License Instructions

**CRITICAL: This file is licensed under GPL v2+ (not MIT)**

## Important Guidelines

1. **License Compatibility**: This file is derived from WordPress's `wptexturize()` function and MUST remain under GPL v2 or later license.

2. **Isolation Required**: Keep this file isolated from the main MIT-licensed codebase. Changes to this file should not be copied to other parts of the application.

3. **Header Maintenance**: Always preserve the GPL license header at the top of the file. Do not remove or modify the copyright notices.

4. **WordPress Attribution**: Maintain attribution to WordPress and link to the original source code.

5. **Modifications**: When modifying this file:
   - Add your changes after the existing copyright notices
   - Document significant changes in comments
   - Keep the GPL license text intact

6. **Creating Similar Functionality**: If you need similar functionality elsewhere in the app:
   - DO NOT copy code from this file to MIT-licensed files
   - Write new implementations from scratch
   - Use different algorithms and approaches

## Why This Matters

The app uses a dual-license structure:
- **Main Application**: MIT License (permissive)
- **Texturizer Component**: GPL v2+ (copyleft)

Mixing GPL code into MIT-licensed files could create license violations. Keep them separate.

## If You Need to Extend Typography Features

If new typography features are needed outside of Texturizer:
1. Consider if the feature truly needs to be separate from Texturizer
2. If separate, implement it from scratch in a new MIT-licensed file
3. Do not reference or copy from Texturizer.swift
4. Document the new implementation's approach and license clearly
