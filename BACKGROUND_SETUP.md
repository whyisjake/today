# Background Modes Setup Guide

Follow these steps exactly to enable background syncing in your Today app.

## Step 1: Open Project Settings

1. In Xcode, click on the **blue "Today" project file** at the very top of the Project Navigator (left sidebar)
   - It's the first item with a blue icon
2. Make sure you're viewing the **"Today" target** (not the project)
   - In the main editor area, you'll see a list under "TARGETS" - click on "Today"

## Step 2: Add Background Modes Capability

1. Click on the **"Signing & Capabilities"** tab at the top of the editor area
   - You'll see tabs: General, Signing & Capabilities, Resource Tags, Info, Build Settings, etc.
2. Click the **"+ Capability"** button
   - It's near the top left, below the tabs
3. A popup will appear with a search box
4. Type **"background"** in the search
5. Double-click on **"Background Modes"**
6. A new section called "Background Modes" will appear
7. In that section, check the box next to **"Background fetch"**
   - There are several checkboxes (Remote notifications, Background fetch, etc.)
   - Just check "Background fetch"

## Step 3: Add Background Task Identifier

1. In the same project settings, click on the **"Info"** tab
   - It's right next to "Signing & Capabilities"
2. You'll see a list of keys and values
3. Hover over any row and click the **"+"** button that appears
4. In the new row that appears:
   - **Key**: Type or paste: `Permitted background task scheduler identifiers`
   - **Type**: Change from "String" to **"Array"** using the dropdown
5. Click the disclosure triangle (▶) next to your new key to expand it
6. Click the **"+"** button that appears under the array
7. In the new "Item 0" row:
   - **Type**: String (leave as is)
   - **Value**: Type or paste: `com.today.feedsync`

Your Info.plist should now look like this:
```
▼ Permitted background task scheduler identifiers    Array    (1 item)
    Item 0                                            String   com.today.feedsync
```

## Step 4: Build and Run

1. Press **Cmd+B** to build (or Product > Build from menu)
2. If there are no errors, press **Cmd+R** to run (or Product > Run)

## Testing Background Sync

Once the app is running in the simulator or on a device:

1. Add some RSS feeds in the app
2. In Xcode menu bar, go to **Debug > Simulate Background Fetch**
3. The app will sync feeds in the background
4. Check the Xcode console for log messages like "Starting background sync..."

## Troubleshooting

**"I don't see the + Capability button"**
- Make sure you clicked on the TARGET (not the project)
- Make sure you're on the "Signing & Capabilities" tab

**"I can't find Permitted background task scheduler identifiers"**
- You need to ADD it manually - it's not in the default list
- Just click + on any row and start typing the key name

**"Background sync never runs"**
- In the simulator, you must manually trigger it with Debug > Simulate Background Fetch
- On a real device, iOS decides when to run it (could be hours)
- Background fetch is intentionally limited by iOS to save battery

**"The app won't build"**
- Make sure you added the Combine import (I just fixed this)
- Try cleaning: Shift+Cmd+K
- Try closing and reopening Xcode

## Optional: Visual Confirmation

If you want to see what Background Modes looks like when configured correctly, it should show:

```
Background Modes
✓ Background fetch
```

And in Info.plist:
```
Permitted background task scheduler identifiers
  Item 0: com.today.feedsync
```

That's it! Let me know if you get stuck on any step.
