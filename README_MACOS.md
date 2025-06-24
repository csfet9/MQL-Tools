# MQL Tools for macOS with Apple Silicon (M1/M2/M3)

This fork of MQL Tools has been modified to work on macOS, including Apple Silicon devices, through Parallels Desktop.

## Requirements

1. **Parallels Desktop Pro** - Required for running MetaTrader and MetaEditor
2. **Windows 11 VM** - Running in Parallels with MetaTrader 4/5 installed
3. **Shared Folders** - Enabled between macOS and Windows VM

## Installation

1. Install the extension from VS Code
2. Configure your Parallels VM name in VS Code settings:
   - Open VS Code Settings (Cmd+,)
   - Search for "MQL Tools"
   - Set `Parallels: VM Name` to match your Windows VM name (default: "Windows 11")

## Configuration

### Path Configuration

The extension automatically converts Windows paths to macOS paths. When configuring MetaEditor paths:

1. **Windows Paths in VM**: Use the Windows paths as they appear inside your VM
   - Example: `C:\Program Files\MetaTrader 5\metaeditor64.exe`

2. **Shared Folder Access**: The extension will automatically convert these to Parallels shared folder paths
   - Converts to: `/Volumes/C/Program Files/MetaTrader 5/metaeditor64.exe`

### Recommended Setup

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
     "mql_tools.Metaeditor.Metaeditor4Dir": "C:\\Program Files\\MetaTrader 4\\metaeditor.exe",
     "mql_tools.Metaeditor.Metaeditor5Dir": "C:\\Program Files\\MetaTrader 5\\metaeditor64.exe",
     "mql_tools.Parallels.vmName": "Windows 11"
   }
   ```

## Features

All features work on macOS through Parallels:

- ✅ **Syntax Checking** - Validates MQL code without compilation
- ✅ **Compilation** - Compiles MQ4/MQ5 files through MetaEditor in Parallels
- ✅ **Script Compilation** - Opens MetaEditor in VM and compiles
- ✅ **Help Files** - Opens CHM help files (requires CHM viewer on macOS or uses Parallels)
- ✅ **MetaEditor Integration** - Opens files directly in MetaEditor

## Troubleshooting

### Extension Not Found in VS Code

The extension now supports macOS ARM64. If you still can't find it:
1. Search for "MQL Tools" in VS Code Extensions
2. Make sure you're using the latest version of VS Code

### Compilation Errors

1. **Check VM Name**: Ensure the Parallels VM name in settings matches your actual VM name
2. **Check Paths**: Verify MetaEditor paths are correct within the Windows VM
3. **Shared Folders**: Ensure Parallels shared folders are enabled

### Path Issues

If paths aren't working correctly:
1. Check if the file exists at the converted path
2. Try using the full Windows path including drive letter
3. Ensure no special characters in file paths

### Parallels Commands

The extension uses `prlctl` to execute commands in the VM. Ensure:
1. Parallels Desktop is running
2. Your Windows VM is running
3. Parallels Tools are installed in the VM

## Alternative Setups

### Using Network Shares

Instead of Parallels shared folders, you can use SMB shares:
1. Share your MQL folders from Windows
2. Mount them on macOS
3. Work directly with the mounted folders

### Wine/CrossOver

For basic editing without compilation, you might use Wine or CrossOver, but compilation features require actual Windows MetaEditor.

## Known Limitations

1. **Performance**: Compilation through Parallels may be slower than native Windows
2. **Help Files**: CHM files require a macOS CHM viewer or will open through Parallels
3. **Real-time Updates**: File watching may have slight delays through shared folders

## Support

For issues specific to macOS/Parallels integration, please create an issue on the GitHub repository with:
- Your macOS version
- Parallels Desktop version
- Windows VM version
- Error messages or logs 