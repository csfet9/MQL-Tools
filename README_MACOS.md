# MQL Tools for macOS with Apple Silicon (M1/M2/M3)

This fork of MQL Tools has been modified to work on macOS, including Apple Silicon devices, with **Wine as the default integration method** and Parallels Desktop as a fallback option.

## Requirements

### Wine Integration (Default - Recommended)

1. **Wine** - For running MetaTrader and MetaEditor natively on macOS
2. **MetaTrader 5 with Wine** - Official MT5 Wine installation package
3. **Homebrew** - For easy Wine installation and management

### Parallels Integration (Fallback Option)

1. **Parallels Desktop Pro** - Alternative method for running MetaTrader and MetaEditor
2. **Windows 11 VM** - Running in Parallels with MetaTrader 4/5 installed
3. **Shared Folders** - Enabled between macOS and Windows VM

## Installation

### Wine Installation (Recommended)

1. **Install Wine via Homebrew**:
   ```bash
   brew install --cask --no-quarantine wine@staging
   ```

2. **Install MetaTrader 5 with Wine**:
   - Download the official MT5 installer from MetaQuotes
   - The installer automatically sets up Wine and creates the proper Wine prefix
   - Default installation path: `~/Library/Application Support/net.metaquotes.wine.metatrader5/`

3. **Install the MQL Tools extension** from VS Code Extensions marketplace

4. **Configure Wine integration** (optional - auto-detected by default):
   - Open VS Code Settings (Cmd+,)
   - Search for "MQL Tools"
   - Ensure `macOS: Preferred Method` is set to "wine" (default)

### Parallels Installation (Fallback)

1. Install the extension from VS Code
2. Configure your Parallels VM name in VS Code settings:
   - Open VS Code Settings (Cmd+,)
   - Search for "MQL Tools"
   - Set `macOS: Preferred Method` to "parallels"
   - Set `Parallels: VM Name` to match your Windows VM name (default: "Windows 11")

## Configuration

### Wine Configuration (Default)

The extension automatically detects Wine installations and MetaTrader paths. **No manual configuration required** for standard installations.

**Default Wine Paths** (auto-detected):
- Wine Prefix: `~/Library/Application Support/net.metaquotes.wine.metatrader5/`
- MT5 MetaEditor: `drive_c/Program Files/MetaTrader 5/metaeditor64.exe`
- MT4 MetaEditor: `drive_c/Program Files/MetaTrader 4/metaeditor.exe`

**Extension Settings** (Wine as default):
```json
{
  "mql_tools.macOS.preferredMethod": "wine",
  "mql_tools.Wine.autoDetect": true
}
```

### Parallels Configuration (Fallback)

When using Parallels instead of Wine:

1. **Windows Paths in VM**: Use the Windows paths as they appear inside your VM
   - Example: `C:\Program Files\MetaTrader 5\metaeditor64.exe`

2. **Shared Folder Access**: The extension will automatically convert these to Parallels shared folder paths
   - Converts to: `/Volumes/C/Program Files/MetaTrader 5/metaeditor64.exe`

**Parallels Setup**:

1. **Install MetaTrader in Windows VM**:
   ```
   C:\Program Files\MetaTrader 4\
   C:\Program Files\MetaTrader 5\
   ```

2. **Enable Parallels Shared Folders**:
   - Open Parallels Configuration for your VM
   - Go to Options > Sharing
   - Enable "Share Mac volumes with Windows"

3. **Configure Extension Settings**:
   ```json
   {
     "mql_tools.macOS.preferredMethod": "parallels",
     "mql_tools.Metaeditor.Metaeditor4Dir": "C:\\Program Files\\MetaTrader 4\\metaeditor.exe",
     "mql_tools.Metaeditor.Metaeditor5Dir": "C:\\Program Files\\MetaTrader 5\\metaeditor64.exe",
     "mql_tools.Parallels.vmName": "Windows 11"
   }
   ```

## Features

All features work on macOS through Wine (default) or Parallels (fallback):

- ✅ **Syntax Checking** - Validates MQL code without compilation
- ✅ **Compilation** - Compiles MQ4/MQ5 files through MetaEditor via Wine or Parallels
- ✅ **Script Compilation** - Opens MetaEditor and compiles automatically
- ✅ **Help Files** - Opens CHM help files (requires CHM viewer on macOS)
- ✅ **MetaEditor Integration** - Opens files directly in MetaEditor
- ✅ **Automatic Method Detection** - Automatically chooses Wine or Parallels based on availability

## Troubleshooting

### Extension Not Found in VS Code

The extension now supports macOS ARM64. If you still can't find it:
1. Search for "MQL Tools" in VS Code Extensions
2. Make sure you're using the latest version of VS Code

### Wine-Related Issues

1. **Wine Not Detected**:
   - Verify Wine installation: `which wine`
   - Reinstall Wine: `brew install --cask --no-quarantine wine@staging`
   - Check Wine version: `wine --version`

2. **MetaTrader Not Found**:
   - Verify MT5 Wine installation at: `~/Library/Application Support/net.metaquotes.wine.metatrader5/`
   - Reinstall MetaTrader 5 using the official Wine installer
   - Check Wine prefix: `ls ~/Library/Application\ Support/net.metaquotes.wine.metatrader5/drive_c/Program\ Files/`

3. **Compilation Errors with Wine**:
   - Check MetaEditor path in Wine prefix
   - Verify WINEPREFIX environment variable
   - Try switching to Parallels temporarily: Set `macOS.preferredMethod` to "parallels"

### Parallels-Related Issues (Fallback)

1. **Check VM Name**: Ensure the Parallels VM name in settings matches your actual VM name
2. **Check Paths**: Verify MetaEditor paths are correct within the Windows VM
3. **Shared Folders**: Ensure Parallels shared folders are enabled

### Path Issues

If paths aren't working correctly:
1. Check if the file exists at the converted path
2. Try using the full Windows path including drive letter
3. Ensure no special characters in file paths
4. For Wine: Verify the Wine prefix structure

### Method Switching

To switch between Wine and Parallels:
1. Open VS Code Settings (Cmd+,)
2. Search for "MQL Tools"
3. Change `macOS: Preferred Method` to "wine" or "parallels"
4. Restart VS Code for changes to take effect

## Alternative Setups

### Wine (Primary Method)

Wine is now the primary integration method, providing:
- **Native Performance**: Runs MetaEditor directly on macOS without VM overhead
- **Automatic Setup**: Official MT5 Wine installer handles Wine configuration
- **Lower Resource Usage**: No need for full Windows VM
- **Faster Compilation**: Direct execution without VM communication overhead

### Parallels Desktop (Fallback Method)

Parallels remains available as a fallback option:
- **Full Windows Compatibility**: Complete Windows environment
- **Shared Folders**: Easy file access between macOS and Windows
- **Proven Stability**: Well-tested integration method

### Using Network Shares (Advanced)

For advanced setups, you can use SMB shares:
1. Share your MQL folders from Windows (if using Parallels)
2. Mount them on macOS
3. Work directly with the mounted folders

## Known Limitations

### Wine Integration
1. **Help Files**: CHM files require a macOS CHM viewer (e.g., Chmox, CHM Viewer)
2. **Wine Dependencies**: Requires Wine installation and proper configuration
3. **Rosetta 2**: Wine on Apple Silicon requires Rosetta 2 for x86 compatibility

### Parallels Integration
1. **Performance**: Compilation through Parallels may be slower than Wine
2. **Resource Usage**: Requires running full Windows VM
3. **Real-time Updates**: File watching may have slight delays through shared folders
4. **VM Management**: Requires Parallels Desktop Pro license

### General
1. **First-time Setup**: Initial Wine or Parallels configuration may require some setup
2. **Path Handling**: Complex path structures may need manual configuration

## Support

For issues specific to macOS/Parallels integration, please create an issue on the GitHub repository with:
- Your macOS version
- Parallels Desktop version
- Windows VM version
- Error messages or logs  