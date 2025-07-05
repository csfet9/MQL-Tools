'use strict';
const os = require('os');
const pathModule = require('path');
const fs = require('fs');

let volumesCache = null;
let volumesCacheTime = 0;
const CACHE_DURATION = 30000; // 30 seconds

function getVolumes() {
    const now = Date.now();
    if (!volumesCache || (now - volumesCacheTime) > CACHE_DURATION) {
        try {
            volumesCache = fs.readdirSync('/Volumes');
            volumesCacheTime = now;
        } catch (error) {
            volumesCache = [];
            volumesCacheTime = now;
        }
    }
    return volumesCache;
}

// Detect the current platform
const platform = os.platform();
const isWindows = platform === 'win32';
const isMac = platform === 'darwin';
const isLinux = platform === 'linux';

// Check if running on ARM architecture
const isARM = os.arch() === 'arm64' || os.arch() === 'arm';

/**
 * Check if Wine is installed on the system
 * @returns {boolean} - True if Wine is installed, false otherwise
 */
function checkWineInstallation() {
    try {
        require('child_process').execSync('which wine', { stdio: 'ignore' });
        return true;
    } catch {
        return false;
    }
}

/**
 * Detect Wine MetaTrader installation and paths
 * @returns {Object} - Wine installation information
 */
function detectWineMetaTrader() {
    const winePrefix = pathModule.join(os.homedir(), 'Library/Application Support/net.metaquotes.wine.metatrader5');
    const mt5Path = pathModule.join(winePrefix, 'drive_c/Program Files/MetaTrader 5');
    const mt4Path = pathModule.join(winePrefix, 'drive_c/Program Files/MetaTrader 4');
    
    return {
        hasWinePrefix: fs.existsSync(winePrefix),
        hasMT5: fs.existsSync(mt5Path),
        hasMT4: fs.existsSync(mt4Path),
        winePrefix,
        mt5Path,
        mt4Path
    };
}

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
    const volumes = getVolumes();
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
    
    // Clean up any double slashes (except at the beginning for UNC paths)
    macPath = macPath.replace(/([^:])\/\//g, '$1/');
    
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
    const volumes = getVolumes();
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
 * Convert Windows path to Wine prefix path
 * @param {string} windowsPath - Windows path to convert
 * @returns {string} - Wine prefix path
 */
function convertPathForWine(windowsPath) {
    if (!windowsPath || isWindows) return windowsPath;
    
    const wineInfo = detectWineMetaTrader();
    if (!wineInfo.hasWinePrefix) return windowsPath;
    
    // Convert Windows path to Wine prefix path
    let winePath = windowsPath;
    winePath = winePath.replace(/^C:\\/i, wineInfo.winePrefix + '/drive_c/');
    winePath = winePath.replace(/^D:\\/i, wineInfo.winePrefix + '/drive_d/');
    winePath = winePath.replace(/\\/g, '/');
    
    return winePath;
}

/**
 * Get Wine environment variables for command execution
 * @returns {Object} - Environment variables for Wine
 */
function getWineEnvironment() {
    const wineInfo = detectWineMetaTrader();
    return wineInfo.hasWinePrefix ? {
        ...process.env,
        WINEPREFIX: wineInfo.winePrefix,
        WINEDEBUG: '-all'
    } : process.env;
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
 * @param {Object} options - Additional options for command execution
 */
function executeCommand(command, callback, options = {}) {
    const childProcess = require('child_process');
    const vscode = require('vscode');
    
    if (isMac && command.includes('.exe')) {
        const preferredMethod = vscode.workspace.getConfiguration('mql_tools').get('macOS.preferredMethod', 'wine');
        
        if (preferredMethod === 'wine' && checkWineInstallation()) {
            const wineCommand = `wine "${convertPathForWine(command)}"`;
            childProcess.exec(wineCommand, { 
                env: getWineEnvironment(),
                ...options 
            }, callback);
        } else if (preferredMethod === 'parallels' || !checkWineInstallation()) {
            // Fallback to existing Parallels logic
            const vmName = vscode.workspace.getConfiguration('mql_tools').get('Parallels.vmName', 'Windows 11');
            const parallelCommand = `prlctl exec "${vmName}" ${command}`;
            childProcess.exec(parallelCommand, options, callback);
        } else {
            callback(new Error('Neither Wine nor Parallels is available for MetaEditor execution'));
        }
    } else {
        childProcess.exec(command, options, callback);
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
        const wineInfo = detectWineMetaTrader();
        if (wineInfo.hasWinePrefix) {
            return {
                metaeditor4: pathModule.join(wineInfo.mt4Path, 'metaeditor.exe'),
                metaeditor5: pathModule.join(wineInfo.mt5Path, 'metaeditor64.exe')
            };
        } else {
            // Fallback to Parallels paths
            return {
                metaeditor4: "/Volumes/C/MT4_Install/MetaTrader/metaeditor.exe",
                metaeditor5: "/Volumes/C/MT5_Install/MetaTrader/metaeditor.exe"
            };
        }
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
    convertPathForWine,
    getPlatformExecutable,
    executeCommand,
    getPlatformDefaults,
    checkWineInstallation,
    detectWineMetaTrader,
    getWineEnvironment
};                      