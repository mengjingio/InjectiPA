//
//  Utils.swift
//  InjectiPA
//
//  Created by TrialMacApp on 2025-02-17.
//

import SwiftUI
import AppKit
import Foundation

public struct IPAInfo: Identifiable {
    public let id = UUID()
    public var name: String
    public var bundleID: String
    public var version: String
    public var icon: NSImage?
    public var dylibs: [String]
    public var url: URL
}

extension Utils {
    public static func parseIPA(ipaPath: URL) -> IPAInfo? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try unzipIPA(ipaPath: ipaPath, to: tempDir)

            let payload = tempDir.appendingPathComponent("Payload")
            let contents = try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
            guard let appURL = contents.first(where: { $0.pathExtension == "app" }) else {
                try? FileManager.default.removeItem(at: tempDir)
                return nil
            }

            // Info.plist
            let infoPlistURL = appURL.appendingPathComponent("Info.plist")
            var name = appURL.deletingPathExtension().lastPathComponent
            var bundleID = ""
            var version = ""

            if let data = try? Data(contentsOf: infoPlistURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                if let displayName = plist["CFBundleDisplayName"] as? String {
                    name = displayName
                } else if let bundleName = plist["CFBundleName"] as? String {
                    name = bundleName
                }
                bundleID = plist["CFBundleIdentifier"] as? String ?? ""
                if let short = plist["CFBundleShortVersionString"] as? String,
                   let build = plist["CFBundleVersion"] as? String {
                    version = "\(short) (\(build))"
                } else {
                    version = plist["CFBundleVersion"] as? String ?? ""
                }

                // 尝试从 Info.plist 指定的图标中寻找
                if let icons = plist["CFBundleIcons"] as? [String: Any],
                   let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
                   let files = primary["CFBundleIconFiles"] as? [String],
                   let first = files.last {
                    // 在 app 目录中查找对应文件
                    let candidates = try FileManager.default.contentsOfDirectory(at: appURL, includingPropertiesForKeys: nil)
                    if let found = candidates.first(where: { $0.lastPathComponent.contains(first) && $0.pathExtension.lowercased() == "png" }) {
                        let img = NSImage(contentsOf: found)
                        try? FileManager.default.removeItem(at: tempDir)
                        let dylibs = findDylibs(in: appURL)
                        return IPAInfo(name: name, bundleID: bundleID, version: version, icon: img, dylibs: dylibs, url: ipaPath)
                    }
                }
            }

            // 退而求其次：寻找最大的 png 作为图标
            var bestImage: NSImage? = nil
            var bestSize: UInt64 = 0
            let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: [.fileSizeKey])
            while let item = enumerator?.nextObject() as? URL {
                if item.pathExtension.lowercased() == "png" {
                    if let attr = try? item.resourceValues(forKeys: [.fileSizeKey]), let fs = attr.fileSize {
                        if UInt64(fs) > bestSize {
                            bestSize = UInt64(fs)
                            bestImage = NSImage(contentsOf: item)
                        }
                    }
                }
            }

            let dylibs = findDylibs(in: appURL)
            try? FileManager.default.removeItem(at: tempDir)
            return IPAInfo(name: name, bundleID: bundleID, version: version, icon: bestImage, dylibs: dylibs, url: ipaPath)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }
    }

    private static func findDylibs(in appURL: URL) -> [String] {
        var found: [String] = []
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: appURL, includingPropertiesForKeys: nil) {
            while let item = enumerator.nextObject() as? URL {
                if item.pathExtension.lowercased() == "dylib" {
                    found.append(item.lastPathComponent)
                }
            }
        }
        // Also check Frameworks folder
        let frameworks = appURL.appendingPathComponent("Frameworks")
        if fm.fileExists(atPath: frameworks.path) {
            if let items = try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil) {
                for it in items where it.pathExtension.lowercased() == "dylib" {
                    found.append(it.lastPathComponent)
                }
            }
        }
        return found
    }
}

class Utils {
    public static func unzipIPA(ipaPath: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", ipaPath.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
    }

    public static func zipFolder(sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destinationURL.path, "."]
        process.currentDirectoryURL = sourceURL
        try process.run()
        process.waitUntilExit()
    }
    
//    public static func debToDylib(debPath: URL, to destination: URL) throws {
//        let process = Process()
//        process.executableURL = URL(fileURLWithPath: "/usr/bin/ar")
//        process.arguments = ["x", debPath.path]
//        process.currentDirectoryURL = destination
//        try process.run()
//        process.waitUntilExit()
//    }
//
//    public static func debToLzma(debPath: URL, to destination: URL) throws {
//        let process = Process()
//        process.executableURL = URL(fileURLWithPath: "/usr/bin/ar")
//        process.arguments = ["x", debPath.path]
//        process.currentDirectoryURL = destination
//        try process.run()
//        process.waitUntilExit()
//    }
//
//    public static func unzipLzma(debPath: URL, to destination: URL) throws {
//        let process = Process()
//        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
//        process.arguments = ["x", debPath.path]
//        process.currentDirectoryURL = destination
//        try process.run()
//        process.waitUntilExit()
//    }

    public static func getExecutableName(_ appPath: String) -> String? {
        let infoPlistPath = "\(appPath)/Info.plist"
        let url = URL(fileURLWithPath: infoPlistPath)

        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executableName = plist["CFBundleExecutable"] as? String
        else {
            return nil
        }

        return executableName
    }
}

enum DebExtractionError: Error {
    case arExtractionFailed
    case tarExtractionFailed
    case dylibNotFound
    case fileOperationFailed(String)
}

public class DebExtractor {
    public static func debToDylib(debPath: URL, to destination: URL) throws -> String {
        // 创建临时工作目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        do {
            // 第一步：解压deb文件
            try extractDeb(debPath: debPath, to: tempDir)
            
            // 第二步：解压data.tar.*文件
            try extractTar(in: tempDir)
            
            // 第三步：查找并移动dylib文件
            let filename = try findAndMoveDylib(from: tempDir, to: destination)
            
            // 清理临时文件
            try FileManager.default.removeItem(at: tempDir)
            return filename
        } catch {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }
    
    private static func extractDeb(debPath: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ar")
        process.arguments = ["x", debPath.path]
        process.currentDirectoryURL = destination
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw DebExtractionError.arExtractionFailed
        }
    }
    
    private static func extractTar(in directory: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        
        // 查找data.tar.*文件
        guard let tarFile = contents.first(where: { $0.lastPathComponent.starts(with: "data.tar") }) else {
            throw DebExtractionError.fileOperationFailed("data.tar.* file not found")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xf", tarFile.path]
        process.currentDirectoryURL = directory
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw DebExtractionError.tarExtractionFailed
        }
    }
    
    private static func findAndMoveDylib(from sourceDir: URL, to destinationDir: URL) throws -> String {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: [.isRegularFileKey])
        var dylibFound = false
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let fileExtension = fileURL.pathExtension.lowercased()
            if fileExtension == "dylib" {
                let fileName = fileURL.lastPathComponent
                let destinationURL = destinationDir.appendingPathComponent(fileName)
                
                try fileManager.copyItem(at: fileURL, to: destinationURL)
                return fileName
            }
        }
        
        if !dylibFound {
            throw DebExtractionError.dylibNotFound
        }
    }
}
