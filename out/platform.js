'use strict';
const os = require('os');
const pathModule = require('path');
const fs = require('fs');

// Detect the current platform
const platform = os.platform();
const isWindows = platform === 'win32';
const isMac = platform === 'darwin';
const isLinux = platform === 'linux';

// Check if running on ARM architecture
const isARM = os.arch() === 'arm64' || os.arch() === 'arm';

/**
 * Convert Windows path to Parallels shared folder path
 * @param {string} windowsPath - Windows path from configuration
 * @returns {string} - Converted path for macOS
 */
function convertWindowsPathToMac(windowsPath) {
    if (!windowsPath || isWindows) return windowsPath;
    
    // Common Parallels shared folder patterns
    // C:\\ -> /Volumes/[C] Windows 11/
    // \\Mac\Home -> /Users/
    
    let macPath = windowsPath;
    
    // First, try to find the actual Parallels mount point
    const volumes = fs.readdirSync('/Volumes');
    let cDrivePath = null;
    let dDrivePath = null;
    
    // Look for Parallels-style mount points
    volumes.forEach(vol => {
        if (vol.includes('[C]') || vol.toLowerCase().includes('windows')) {
            cDrivePath = `/Volumes/${vol}`;
        }
        if (vol.includes('[D]')) {
            dDrivePath = `/Volumes/${vol}`;
        }
    });
    
    // Replace Windows drive letters with actual Parallels mount points
    if (cDrivePath && macPath.match(/^C:\\/i)) {
        macPath = macPath.replace(/^C:\\/i, cDrivePath + '/');
    } else if (dDrivePath && macPath.match(/^D:\\/i)) {
        macPath = macPath.replace(/^D:\\/i, dDrivePath + '/');
    } else {
        // Fallback to standard conversion
        macPath = macPath.replace(/^([A-Z]):\\/i, '/Volumes/$1/');
    }
    
    // Replace backslashes with forward slashes
    macPath = macPath.replace(/\\/g, '/');
    
    // Handle UNC paths (\\Mac\Home)
    macPath = macPath.replace(/^\\\\Mac\\Home/i, os.homedir());
    
    // Check for alternative Parallels paths if the primary path doesn't exist
    if (!fs.existsSync(macPath) && macPath.startsWith('/Volumes/')) {
        // Try alternative Parallels paths
        const alternativePaths = [
            macPath.replace('/Volumes/', '/private/var/folders/parallels/'),
            macPath.replace('/Volumes/', '/Users/Shared/Parallels/'),
            os.homedir() + '/Parallels/' + macPath.substring(macPath.lastIndexOf('/'))
        ];
        
        for (const altPath of alternativePaths) {
            if (fs.existsSync(altPath)) {
                return altPath;
            }
        }
    }
    
    return macPath;
}

/**
 * Convert macOS path to Windows path for MetaEditor
 * @param {string} macPath - macOS path
 * @returns {string} - Windows path for MetaEditor in Parallels
 */
function convertMacPathToWindows(macPath) {
    if (!macPath || isWindows) return macPath;
    
    let windowsPath = macPath;
    
    // Find actual Parallels mount points
    const volumes = fs.readdirSync('/Volumes');
    volumes.forEach(vol => {
        if (vol.includes('[C]') || vol.toLowerCase().includes('windows')) {
            // Convert Parallels mount point back to Windows C: drive
            windowsPath = windowsPath.replace(new RegExp(`^/Volumes/${vol.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/`, 'i'), 'C:\\');
        }
        if (vol.includes('[D]')) {
            // Convert Parallels mount point back to Windows D: drive
            windowsPath = windowsPath.replace(new RegExp(`^/Volumes/${vol.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/`, 'i'), 'D:\\');
        }
    });
    
    // Fallback conversion for standard mount points
    windowsPath = windowsPath.replace(/^\/Volumes\/([A-Z])\//i, '$1:\\');
    
    // Convert home directory to Windows UNC path
    windowsPath = windowsPath.replace(new RegExp('^' + os.homedir()), '\\\\Mac\\Home');
    
    // Replace forward slashes with backslashes
    windowsPath = windowsPath.replace(/\//g, '\\');
    
    return windowsPath;
}

/**
 * Get platform-specific executable path
 * @param {string} windowsExe - Windows executable name
 * @returns {string} - Platform-specific executable path
 */
function getPlatformExecutable(windowsExe) {
    if (isWindows) return windowsExe;
    
    // For macOS, we need to use Parallels to run Windows executables
    // or provide alternative implementations
    if (windowsExe.includes('metaeditor')) {
        // MetaEditor needs to run through Parallels
        return `open -a "Parallels Desktop" --args "${windowsExe}"`;
    }
    
    return windowsExe;
}

/**
 * Execute command with platform-specific handling
 * @param {string} command - Command to execute
 * @param {Function} callback - Callback function
 */
function executeCommand(command, callback) {
    const childProcess = require('child_process');
    
    if (isMac && command.includes('.exe')) {
        // For macOS, try to execute through Parallels
        const parallelCommand = `prlctl exec {vm-name} ${command}`;
        childProcess.exec(parallelCommand, callback);
    } else {
        childProcess.exec(command, callback);
    }
}

/**
 * Get platform-specific configuration defaults
 * @returns {Object} - Configuration defaults
 */
function getPlatformDefaults() {
    if (isWindows) {
        return {
            metaeditor4: "C:\\MT4_Install\\MetaTrader\\metaeditor.exe",
            metaeditor5: "C:\\MT5_Install\\MetaTrader\\metaeditor.exe"
        };
    } else if (isMac) {
        return {
            metaeditor4: "/Volumes/C/MT4_Install/MetaTrader/metaeditor.exe",
            metaeditor5: "/Volumes/C/MT5_Install/MetaTrader/metaeditor.exe"
        };
    } else {
        return {
            metaeditor4: "/mnt/c/MT4_Install/MetaTrader/metaeditor.exe",
            metaeditor5: "/mnt/c/MT5_Install/MetaTrader/metaeditor.exe"
        };
    }
}

module.exports = {
    platform,
    isWindows,
    isMac,
    isLinux,
    isARM,
    convertWindowsPathToMac,
    convertMacPathToWindows,
    getPlatformExecutable,
    executeCommand,
    getPlatformDefaults
}; 