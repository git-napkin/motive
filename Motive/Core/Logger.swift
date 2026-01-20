//
//  Logger.swift
//  Motive
//
//  Debug logging utility that only prints in DEBUG builds.
//

import Foundation
import os.log

/// Debug logger that only outputs in DEBUG builds
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.velvet.motive"
    
    private static let appLogger = os.Logger(subsystem: subsystem, category: "App")
    private static let bridgeLogger = os.Logger(subsystem: subsystem, category: "Bridge")
    private static let permissionLogger = os.Logger(subsystem: subsystem, category: "Permission")
    private static let configLogger = os.Logger(subsystem: subsystem, category: "Config")
    
    /// Log general app messages
    static func debug(_ message: String, file: String = #file, function: String = #function) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        appLogger.debug("[\(filename):\(function)] \(message)")
        #endif
    }
    
    /// Log OpenCode bridge messages
    static func bridge(_ message: String) {
        #if DEBUG
        bridgeLogger.debug("\(message)")
        #endif
    }
    
    /// Log permission-related messages
    static func permission(_ message: String) {
        #if DEBUG
        permissionLogger.debug("\(message)")
        #endif
    }
    
    /// Log configuration messages
    static func config(_ message: String) {
        #if DEBUG
        configLogger.debug("\(message)")
        #endif
    }
    
    /// Log errors (always logged, even in release)
    static func error(_ message: String, file: String = #file, function: String = #function) {
        let filename = (file as NSString).lastPathComponent
        appLogger.error("[\(filename):\(function)] \(message)")
    }
    
    /// Log warnings (always logged)
    static func warning(_ message: String) {
        appLogger.warning("\(message)")
    }
}
